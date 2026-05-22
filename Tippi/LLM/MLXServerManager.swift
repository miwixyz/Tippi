import Foundation

// MARK: - MLXServerManager

/// Manages the lifecycle of a local `mlx_lm.server` process.
/// Tippi starts the server on first MLX request and keeps it running until the app quits.
@MainActor
final class MLXServerManager: ObservableObject {
    static let shared = MLXServerManager()

    @Published private(set) var state: ServerState = .stopped

    enum ServerState: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        var displayLabel: String {
            switch self {
            case .stopped:         return "Stopped"
            case .starting:        return "Starting…"
            case .running(let p):  return "Running on port \(p)"
            case .failed(let msg): return "Error: \(msg)"
            }
        }
    }

    private var process: Process?

    /// The model ID as reported by the running server via /v1/models.
    /// This can differ from the configured model string when the server was
    /// started with a local path instead of a HuggingFace repo ID.
    private(set) var activeModelID: String?

    // MARK: - Configuration keys

    // Uses same key convention as LLMRouter for model ("defaultModel.mlx")
    static let defaultModel = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    static let modelKey  = "defaultModel.mlx"
    static let portKey   = "mlx.port"

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }
    static var port: Int {
        get { UserDefaults.standard.integer(forKey: portKey).nonZero ?? 8080 }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }

    // MARK: - Start

    /// Start the server if it isn't already running.
    /// - Returns: The port the server is listening on.
    func start() async throws -> Int {
        if case .running(let p) = state { return p }
        if state == .starting {
            // Wait for existing startup
            return try await waitUntilRunning()
        }

        let model = Self.model
        let port  = Self.port
        state = .starting

        let binary = Self.resolvedBinary()
        guard let binary else {
            let msg = "mlx_lm.server not found. Install with: uv tool install mlx-lm"
            state = .failed(msg)
            throw MLXError.serverNotFound
        }

        // If a compatible server is already listening on the configured port,
        // use it instead of killing user-owned MLX processes.
        if let existingModelID = await fetchActiveModelID(port: port) {
            activeModelID = existingModelID
            state = .running(port: port)
            return port
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary.path)
        proc.arguments     = binary.arguments + [
            "--model", model,
            "--port",  "\(port)"
        ]
        // Suppress server logs from appearing in Tippi console
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                if case .running = self?.state { self?.state = .stopped }
            }
        }

        do {
            try proc.run()
        } catch {
            state = .failed(error.localizedDescription)
            throw MLXError.launchFailed(error.localizedDescription)
        }

        process = proc

        // Poll until the server is ready (up to 60 s — first load takes time)
        do {
            let p = try await waitForHealth(port: port, timeout: 60)
            activeModelID = await fetchActiveModelID(port: p)
            state = .running(port: p)
            return p
        } catch {
            proc.terminate()
            process = nil
            let msg = "Server did not become ready in time."
            state = .failed(msg)
            throw MLXError.startupTimeout
        }
    }

    // MARK: - Stop

    func stop() {
        process?.terminate()
        process = nil
        state = .stopped
        activeModelID = nil
    }

    // MARK: - Binary resolution

    struct ResolvedBinary {
        let path: String
        let arguments: [String]
    }

    /// Try to locate mlx_lm.server in common locations.
    static func resolvedBinary() -> ResolvedBinary? {
        let candidates: [(path: String, args: [String])] = [
            // uv tool install mlx-lm  →  installs here
            ("\(NSHomeDirectory())/.local/bin/mlx_lm.server", []),
            // Homebrew / pipx / manual
            ("/usr/local/bin/mlx_lm.server", []),
            ("/opt/homebrew/bin/mlx_lm.server", []),
            // uvx (zero-install, cached after first run)
            ("\(NSHomeDirectory())/.local/bin/uvx", ["--from", "mlx-lm", "mlx_lm.server"]),
            ("/usr/local/bin/uvx", ["--from", "mlx-lm", "mlx_lm.server"]),
        ]
        for (path, args) in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return ResolvedBinary(path: path, arguments: args)
            }
        }
        return nil
    }

    static var isInstalled: Bool { resolvedBinary() != nil }

    /// The model ID that the running server actually registered (from /v1/models).
    /// Falls back to the configured model string if the server is not yet running.
    static var activeModel: String { shared.activeModelID ?? model }

    // MARK: - Auto-Start

    /// Pre-warm the server in the background if MLX is the user's preferred provider
    /// and the binary is installed. Safe to call from app launch — fails silently
    /// if MLX isn't installed or another provider is preferred.
    static func autoStartIfPreferred() {
        guard isInstalled else { return }
        guard LLMRouter.preferredProviderID == "mlx" else { return }
        Task { @MainActor in
            try? await shared.start()
        }
    }

    /// Restart the server with the current configuration. Convenience for
    /// Settings save flows where the user changed model/port and expects the
    /// server to come back up automatically.
    func restart() async throws -> Int {
        if state.isRunning { stop() }
        return try await start()
    }

    // MARK: - Health polling

    /// Query /v1/models to get the exact model ID the server registered.
    /// When the server is started with a local cache path the ID differs from the
    /// HuggingFace repo string — using this value prevents 404 errors in completions.
    private func fetchActiveModelID(port: Int) async -> String? {
        guard let response = await fetchModels(port: port) else { return nil }
        return response.data.first?.id
    }

    private func waitForHealth(port: Int, timeout: TimeInterval) async throws -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if process?.isRunning == false {
                throw MLXError.startupTimeout
            }
            if await fetchModels(port: port) != nil { return port }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
        }
        throw MLXError.startupTimeout
    }

    private func fetchModels(port: Int) async -> ModelsResponse? {
        let url = URL(string: "http://localhost:\(port)/v1/models")!
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data),
              !decoded.data.isEmpty else {
            return nil
        }
        return decoded
    }

    private func waitUntilRunning() async throws -> Int {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if case .running(let p) = state { return p }
            if case .failed = state { throw MLXError.startupTimeout }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw MLXError.startupTimeout
    }
}

private struct ModelsResponse: Decodable {
    struct ModelEntry: Decodable { let id: String }
    let data: [ModelEntry]
}

// MARK: - MLXError

enum MLXError: LocalizedError {
    case serverNotFound
    case launchFailed(String)
    case startupTimeout

    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            return "mlx_lm.server not found. Install it with: uv tool install mlx-lm"
        case .launchFailed(let msg):
            return "Could not start MLX server: \(msg)"
        case .startupTimeout:
            return "MLX server did not start in time. Try again or check your model path."
        }
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
