import Foundation

// MARK: - MLXServerManager

/// Manages the lifecycle of a local `mlx_lm.server` process.
/// Tippi starts the server on first MLX request and keeps it running until the app quits.
@MainActor
final class MLXServerManager: ObservableObject {
    static let shared = MLXServerManager()

    @Published private(set) var state: ServerState = .stopped

    /// True once the model weights are loaded and the throwaway warm-up request
    /// has completed — i.e. the next real polish will be fast (~0.6 s, not ~2 s).
    /// `.running` alone is NOT enough: `mlx_lm.server` answers /v1/models before
    /// the weights are loaded, so a `.running` server can still be cold.
    @Published private(set) var isWarm = false

    /// Human-readable progress while `mlx_lm.server` fetches model weights from
    /// HuggingFace on first use, e.g. "model-00001-of-00002.safetensors 45%
    /// (1.80G/4.00G)". `nil` when nothing is downloading.
    ///
    /// Tippi never downloads a model itself — it passes a repo ID to
    /// `mlx_lm.server`, which fetches it through `huggingface_hub` into
    /// `~/.cache/huggingface/hub/`. That download reports only on the server's
    /// stderr, which this class used to send to `/dev/null`. The result was a
    /// first run where several GB were quietly downloading behind a UI that
    /// said nothing, and then a flat 60 s timeout that reported "Server did not
    /// become ready in time" — blaming the server for a download that was
    /// working. Surfacing this is what makes the local provider usable on a
    /// slow connection.
    @Published private(set) var downloadStatus: String?

    /// When the last download progress was seen. Drives the idle-based startup
    /// timeout in `waitForHealth`.
    private var lastProgressAt: Date?

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
    static let defaultModel = "mlx-community/gemma-4-e2b-it-4bit"
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
        isWarm = false

        let binary = Self.resolvedBinary()
        guard let binary else {
            let msg = "mlx_lm.server not found. Install with: uv tool install mlx-lm"
            state = .failed(msg)
            throw MLXError.serverNotFound
        }

        // If a server is already listening on the configured port, reuse it
        // instead of killing user-owned MLX processes — but ONLY if it actually
        // serves the model we want. Otherwise the process on this port is a
        // foreign server (LM Studio, LocalAI, llama.cpp, …); silently sending the
        // user's selected text to it would leak that text to an unintended local
        // process and run against the wrong model. Refuse in that case.
        if let existingModelID = await fetchActiveModelID(port: port) {
            guard existingModelID == model else {
                let msg = "Port \(port) is already used by a server serving '\(existingModelID)', not '\(model)'. Change Tippi's MLX port in Settings or stop that server."
                NSLog("Tippi MLX: \(msg)")
                state = .failed(msg)
                throw MLXError.launchFailed(msg)
            }
            activeModelID = existingModelID
            state = .running(port: port)
            // A pre-existing server serving our model is assumed already warm.
            isWarm = true
            return port
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary.path)
        proc.arguments     = binary.arguments + [
            "--model", model,
            "--port",  "\(port)"
        ]
        // stdout stays discarded (request logging, not interesting). stderr is
        // read: that is where huggingface_hub reports the first-run model
        // download, the single slowest thing that can happen here.
        proc.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            // Empty data means EOF. Returning without clearing the handler
            // leaves the dispatch source armed and it re-fires immediately,
            // forever — measured at ~500k calls/second, i.e. a permanently
            // burned CPU core in a background app. Two independent audit runs
            // disagreed on whether this path is reachable in practice; the
            // clear is correct either way, so it is not worth the argument.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard
                  let chunk = String(data: data, encoding: .utf8),
                  let status = Self.parseDownloadProgress(chunk)
            else { return }
            Task { @MainActor in
                // Only meaningful while this start attempt is still in flight.
                guard MLXServerManager.shared.state == .starting else { return }
                MLXServerManager.shared.downloadStatus = status
                MLXServerManager.shared.lastProgressAt = Date()
            }
        }
        proc.terminationHandler = { [weak self] _ in
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                // Exit while we still believed the server was running = an
                // unexpected crash/kill (an explicit stop() sets .stopped BEFORE
                // terminate(), so this branch never fires for that path). Surface
                // it as .failed so the status badge turns red, not stuck yellow.
                if case .running = self?.state {
                    self?.state = .failed("Server exited unexpectedly")
                    self?.isWarm = false
                }
            }
        }

        do {
            try proc.run()
        } catch {
            // `terminationHandler` never fires for a process that never
            // started, so the cleanup it normally performs has to happen here.
            // Without it every failed launch leaks the pipe's file descriptors.
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            state = .failed(error.localizedDescription)
            throw MLXError.launchFailed(error.localizedDescription)
        }

        process = proc

        // Poll until the server is ready. The limit is 60 s of *silence*, not
        // 60 s total — a first-run download legitimately takes minutes.
        do {
            let p = try await waitForHealth(port: port, idleTimeout: 60)
            downloadStatus = nil
            lastProgressAt = nil
            activeModelID = await fetchActiveModelID(port: p)
            state = .running(port: p)
            // /v1/models answers before the model is actually loaded — the first
            // completion pays the weight-load + Metal-kernel-compile cost. Force
            // that now in the background so the user's first real polish is warm.
            warmUpInBackground(port: p, model: activeModelID ?? model)
            return p
        } catch {
            proc.terminate()
            process = nil
            // Name the real cause. A stalled download and a server that failed
            // to boot need different reactions from the user, and the old
            // single message ("did not become ready") sent everyone looking at
            // the server.
            let msg = downloadStatus.map {
                "Model download stalled at \($0). Check the connection and start again — finished parts are cached and will not be re-downloaded."
            } ?? "Server did not become ready in time."
            downloadStatus = nil
            lastProgressAt = nil
            state = .failed(msg)
            throw MLXError.startupTimeout
        }
    }

    /// Mark the server warm from an external success signal — e.g. a real
    /// completion just returned 2xx, which proves the weights are loaded. Lets
    /// the status badge self-heal if the background warm-up probe had failed
    /// transiently. No-op unless the server is currently running.
    func markWarm() {
        if state.isRunning { isWarm = true }
    }

    // MARK: - Stop

    func stop() {
        process?.terminate()
        process = nil
        state = .stopped
        activeModelID = nil
        isWarm = false
        downloadStatus = nil
        lastProgressAt = nil
    }

    // MARK: - Warm-up

    /// Fire-and-forget warm-up. `mlx_lm.server` loads the model lazily, so the
    /// first `/v1/chat/completions` triggers weight load + Metal-kernel
    /// compilation — the cold-start cost measured at ~2 s vs ~0.6 s warm.
    /// Issuing a tiny throwaway request at launch pays that cost in the
    /// background. Best-effort: all errors are ignored.
    private func warmUpInBackground(port: Int, model: String) {
        Task.detached(priority: .utility) {
            guard let url = URL(string: "http://localhost:\(port)/v1/chat/completions") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "hi"]],
                "max_tokens": 1,
                "temperature": 0.0
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            // Only a genuinely successful (2xx) throwaway completion proves the
            // weights are loaded and inference works. A suppressed error
            // (timeout / network / 5xx) must NOT flip the status to warm — that
            // would show "Ready" while the first real polish is still cold or
            // failing.
            let result = try? await URLSession.shared.data(for: req)
            let warmed = (result?.1 as? HTTPURLResponse)
                .map { (200..<300).contains($0.statusCode) } ?? false
            // Also guard against a stop()/restart() that raced in while this
            // request was in flight: never mark a dead server warm.
            await MainActor.run {
                if warmed, MLXServerManager.shared.state.isRunning {
                    MLXServerManager.shared.isWarm = true
                }
            }
        }
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
        // /v1/models lists EVERY model in the HF cache in arbitrary order, so
        // data[0] is often NOT the model this server loaded — using it would make
        // completions POST a foreign model id and force a full model swap on every
        // request. Prefer the entry matching the model we launched with; only fall
        // back to data[0] when the configured model isn't present (e.g. a foreign
        // server already listening on the port), which keeps the reuse-path
        // mismatch warning working.
        let configured = Self.model
        if response.data.contains(where: { $0.id == configured }) {
            return configured
        }
        return response.data.first?.id
    }

    /// Waits for the server to answer `/v1/models`.
    ///
    /// `idleTimeout` is a limit on *silence*, not on total duration: every
    /// reported download byte pushes the deadline out. A flat timeout cannot
    /// work here, because the legitimate first-run case (fetch several GB of
    /// weights over whatever link the user has) and the failure case (server
    /// never boots) differ by orders of magnitude in duration but look
    /// identical from the outside — unless you watch for progress, which is
    /// exactly what `downloadStatus` now provides.
    private func waitForHealth(port: Int, idleTimeout: TimeInterval) async throws -> Int {
        var deadline = Date().addingTimeInterval(idleTimeout)
        while Date() < deadline {
            if process?.isRunning == false {
                throw MLXError.startupTimeout
            }
            if await fetchModels(port: port) != nil { return port }
            if let last = lastProgressAt {
                deadline = max(deadline, last.addingTimeInterval(idleTimeout))
            }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
        }
        throw MLXError.startupTimeout
    }

    /// Extracts a readable line from one chunk of `mlx_lm.server` stderr.
    ///
    /// `huggingface_hub` draws tqdm bars that redraw in place with `\r`, so the
    /// stream is split on `\r` *and* `\n` — splitting on newlines alone yields
    /// nothing at all for the entire duration of a download, which is precisely
    /// the case this exists to report. The newest segment wins, since earlier
    /// ones in the same chunk are already stale redraws.
    ///
    /// Input looks like:
    ///   `model-00001-of-00002.safetensors:  45%|████▌ | 1.80G/4.00G [01:23<01:41, 21.7MB/s]`
    /// `nonisolated` because the stderr `readabilityHandler` fires on a
    /// background queue: this class is `@MainActor`, so an isolated static
    /// would be unreachable from exactly the one caller that needs it. Safe —
    /// the function touches no instance state, only its argument.
    nonisolated static func parseDownloadProgress(_ chunk: String) -> String? {
        for segment in chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).reversed() {
            let line = segment.trimmingCharacters(in: .whitespaces)
            // Require the bar glyph as well as a percentage. A percentage alone
            // appears in ordinary server chatter ("cache hit rate 95%"), and
            // treating that as progress would hold the startup timeout open on
            // a server that is in fact stuck — the failure mode this timeout
            // exists to catch.
            guard line.contains("|"),
                  let percentRange = line.range(of: #"\d+%"#, options: .regularExpression)
            else { continue }
            let percent = String(line[percentRange])

            // The transferred/total fragment sits between the end of the bar
            // ("| ") and the timing bracket (" ["). Both are optional — a bar
            // without them still yields a usable percentage.
            var detail = ""
            if let barEnd = line.range(of: "| ", options: .backwards)?.upperBound,
               let bracket = line.range(of: " [", range: barEnd..<line.endIndex)?.lowerBound {
                detail = line[barEnd..<bracket].trimmingCharacters(in: .whitespaces)
            }

            let label = line.split(separator: ":").first.map(String.init) ?? "Model"
            return detail.isEmpty ? "\(label) \(percent)" : "\(label) \(percent) (\(detail))"
        }
        return nil
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

    /// Waits for a start already in flight.
    ///
    /// Uses the same idle semantics as `waitForHealth`: the limit is 60 s of
    /// silence, not 60 s in total. A flat deadline here meant the two wait
    /// paths answered the same question differently — the first caller waited
    /// patiently through a multi-gigabyte first-run download while every
    /// subsequent one (a polish request, dictation, the auto-start) gave up
    /// after a minute with "MLX server did not start in time", blaming the
    /// server for a download that was progressing normally. That is the exact
    /// message the idle timeout was introduced to get rid of.
    private func waitUntilRunning() async throws -> Int {
        var deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if case .running(let p) = state { return p }
            if case .failed = state { throw MLXError.startupTimeout }
            if let last = lastProgressAt {
                deadline = max(deadline, last.addingTimeInterval(60))
            }
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
