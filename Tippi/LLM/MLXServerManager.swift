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

    // MARK: - Configuration keys

    // Uses same key convention as LLMRouter for model ("defaultModel.mlx")
    static let modelKey  = "defaultModel.mlx"
    static let portKey   = "mlx.port"

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "mlx-community/Qwen3.5-2B-MLX-8bit" }
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

    // MARK: - Health polling

    private func waitForHealth(port: Int, timeout: TimeInterval) async throws -> Int {
        let url      = URL(string: "http://localhost:\(port)/v1/models")!
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let _ = try? await URLSession.shared.data(from: url) { return port }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
        }
        throw MLXError.startupTimeout
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
