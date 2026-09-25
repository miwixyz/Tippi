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

    /// Incremented per start attempt so stderr chunks queued by an earlier
    /// attempt can be told apart from this one's and dropped.
    fileprivate var startGeneration = 0

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
    func start() async throws -> Int { // swiftlint:disable:this function_body_length - Bestand 2026-09-25, 108 Zeilen
        if case .running(let p) = state { return p }
        if state == .starting {
            // Wait for existing startup
            return try await waitUntilRunning()
        }

        let model = Self.model
        let port  = Self.port
        state = .starting
        isWarm = false
        // A stderr chunk from the *previous* attempt can still be sitting in the
        // MainActor queue when this one flips to `.starting`. Landing then, it
        // would push this attempt's idle deadline out by up to a minute and
        // stamp it with the old process's progress text — which then also ends
        // up in the "download stalled at X" message. Clearing the timestamp and
        // bumping the generation makes those late arrivals identifiable.
        lastProgressAt = nil
        downloadStatus = nil
        startGeneration &+= 1
        let generation = startGeneration

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

        // Nothing answered. Before spawning, find out whether the port is even
        // free — a second server cannot bind, and that failure used to surface
        // as a startup timeout that blamed the download.
        if let found = Self.listener(on: port) {
            switch Self.occupantVerdict(listenerPID: found.pid, listenerCommand: found.command) {
            case .staleMLXServer:
                guard Self.clearStaleServer(on: port) else {
                    let msg = String(format: String(localized: "mlx.error.stuckPort"), port)
                    state = .failed(msg)
                    throw MLXError.launchFailed(msg)
                }
            case .foreignProcess(let pid, let command):
                // Never killed: it is not ours, and it might be doing something
                // the user wants. Naming it is the help.
                let name = command.split(separator: " ").first.map(String.init) ?? "unknown"
                let msg = String(format: String(localized: "mlx.error.foreignPort"), port, name, pid)
                state = .failed(msg)
                throw MLXError.launchFailed(msg)
            case .free:
                break
            }
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary.path)
        proc.arguments     = binary.arguments + [
            "--model", model,
            "--port", "\(port)",
            // Pin the bind address instead of inheriting whatever the
            // installed mlx-lm defaults to. Today that default is 127.0.0.1
            // (verified in the installed package), but this server receives
            // the user's selected text — its reachability must not depend on
            // an upstream default that a `uv tool upgrade` could change
            // without anyone noticing. Hardening, added 2026-09-19.
            "--host", "127.0.0.1"
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
                // Only meaningful while *this* start attempt is still in flight.
                // The generation check is what distinguishes it from a later
                // attempt that also happens to be `.starting`.
                guard MLXServerManager.shared.startGeneration == generation,
                      MLXServerManager.shared.state == .starting else { return }
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
            let msg = Self.failureMessage(lastProgress: downloadStatus)
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
        for (path, args) in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return ResolvedBinary(path: path, arguments: args)
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
        if state.isRunning {
            let old = process
            stop()
            // `terminate()` sends SIGTERM and returns immediately. `start()`
            // then asks the port who is serving — and `mlx_lm.server` lists
            // every model in the local HF cache, so the newly chosen one is
            // usually among them. The old, still-dying process therefore looks
            // like a valid server for the new configuration: Tippi adopts it,
            // sets `isWarm = true`, and the model switch silently does not
            // happen. Waiting for the exit removes the ambiguity.
            // Found by audit 2026-09-19.
            if let old, old.isRunning {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        old.waitUntilExit()
                        continuation.resume()
                    }
                }
            }
        }
        return try await start()
    }

    // MARK: - Health polling

    // Query /v1/models to get the exact model ID the server registered.
    // MARK: - A port that is occupied but silent

    /// What is sitting on the configured port, when it does not answer.
    enum PortOccupant: Equatable {
        /// Nothing is listening — free to start.
        case free
        /// A stale `mlx_lm.server`, almost always one Tippi started and then
        /// lost (a crash skips `applicationWillTerminate`). Safe to terminate:
        /// it answers nothing, so it serves nobody.
        case staleMLXServer(pid: Int32)
        /// Something else holds the port. Never killed — naming it is the help.
        case foreignProcess(pid: Int32, command: String)
    }

    /// Decides what to do with a listener that does not answer `/v1/models`.
    ///
    /// Pure, so the decision is testable without opening a socket or spawning
    /// anything. `listenerCommand` is the full command line of whatever holds
    /// the port, or `nil` when nothing does.
    ///
    /// Why this exists (2026-09-20, measured on Michael's Mac): an orphaned
    /// server from an earlier Tippi crash held port 8080 for 27 minutes.
    /// `PPID 1`, 0 % CPU, 22 MB resident — the model never loaded. It accepted
    /// connections and closed them empty, because `mlx_lm.server` logs every
    /// request to stderr and that pipe pointed at the dead parent: the write
    /// failed, the handler died, the reply never came.
    ///
    /// The existing reuse path only handled a listener that *answers*. A silent
    /// one fell through to spawning a second server, which then could not bind,
    /// which surfaced as a startup timeout blaming the download. Every attempt
    /// failed the same way regardless of model — reported as "Fehler kommt bei
    /// allen MLX Modellen", and the port was the reason.
    nonisolated static func occupantVerdict(listenerPID: Int32?, listenerCommand: String?) -> PortOccupant {
        guard let pid = listenerPID, let command = listenerCommand else { return .free }
        // Match the server itself and the uv/uvx wrapper Tippi launches it through.
        if command.contains("mlx_lm.server") || command.contains("mlx-lm") {
            return .staleMLXServer(pid: pid)
        }
        return .foreignProcess(pid: pid, command: command)
    }

    /// Who is listening on `port`, via `lsof`. `nil` when the port is free or
    /// `lsof` is unavailable — the caller then behaves as before.
    nonisolated static func listener(on port: Int) -> (pid: Int32, command: String)? {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice
        do { try lsof.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()
        // Bewusst nicht failable: ungültiges UTF-8 in der lsof-Ausgabe wird ersetzt,
        // statt die ganze Erkennung zu verwerfen.
        // swiftlint:disable:next optional_data_string_conversion
        guard let first = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline).first,
              let pid = Int32(first.trimmingCharacters(in: .whitespaces))
        else { return nil }

        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "command=", "-p", "\(pid)"]
        let psPipe = Pipe()
        ps.standardOutput = psPipe
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return (pid, "") }
        let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        // swiftlint:disable:next optional_data_string_conversion - wie oben: ersetzen statt verwerfen
        let command = String(decoding: psData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (pid, command)
    }

    /// Clears a stale MLX server off `port`. Returns `true` when the port is
    /// free afterwards — verified by looking again, not assumed from the kill
    /// having been issued.
    nonisolated static func clearStaleServer(on port: Int) -> Bool {
        guard let found = listener(on: port) else { return true }
        guard case .staleMLXServer(let pid) = occupantVerdict(listenerPID: found.pid,
                                                              listenerCommand: found.command) else {
            return false
        }
        NSLog("Tippi MLX: terminating stale server pid \(pid) holding port \(port)")
        kill(pid, SIGTERM)
        for _ in 0..<20 {   // up to 2 s
            usleep(100_000)
            if listener(on: port) == nil { return true }
        }
        kill(pid, SIGKILL)
        usleep(300_000)
        return listener(on: port) == nil
    }

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

    /// Turns the last progress line into a message that points at the right
    /// thing — and, crucially, does not point at the wrong one.
    ///
    /// Corrected 2026-09-20 after a real false alarm. A fully cached model
    /// prints `Fetching 8 files: 0%` once and then nothing while several GB of
    /// weights load, so the silence timeout fired and the message said
    /// "Model download stalled — check the connection". Measured on that
    /// machine at the time: all 8 files present, 3.3 GB cached, huggingface.co
    /// answering in 0.18 s, and the server starting in **one second** when run
    /// by hand. The connection was never the problem, and the advice sent the
    /// user to look at it.
    ///
    /// The distinguishing signal is byte progress. `huggingface_hub` prints a
    /// per-file bar with a transferred/total fragment (`1.80G/4.00G`) while
    /// data actually moves; the `Fetching N files` preamble has no such
    /// fragment and appears even when every file is already local.
    nonisolated static func failureMessage(lastProgress: String?) -> String {
        guard let progress = lastProgress else {
            return String(localized: "mlx.error.noAnswer")
        }
        // A transferred/total fragment means bytes were genuinely moving.
        // A unit letter is required on BOTH sides. Without that, `(0/8)` from
        // the `Fetching 8 files` preamble reads as byte progress and the wrong
        // message comes back — the exact failure this function exists to avoid.
        let movedBytes = progress.range(of: #"\d+(\.\d+)?\s*[KMGT]B?\s*/\s*\d+(\.\d+)?\s*[KMGT]B?"#,
                                        options: .regularExpression) != nil
        if movedBytes {
            return String(format: String(localized: "mlx.error.stalled"), progress)
        }
        // No bytes moved: either the files are already local and the weights
        // were still loading, or the server never got that far. Both are fixed
        // by starting again, and neither is a connection problem.
        return String(format: String(localized: "mlx.error.noProgress"), progress)
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
        // The idle rule alone has no upper bound: as long as bytes keep
        // arriving, the deadline keeps moving and this never returns. A
        // multi-gigabyte first-run download would hold a polish request for its
        // entire duration with the activity indicator spinning and no way to
        // cancel. Waiting through a download is right; waiting indefinitely is
        // not, so the idle rule gets a ceiling.
        let hardDeadline = Date().addingTimeInterval(Self.maximumStartupWait)
        while Date() < deadline, Date() < hardDeadline {
            if case .running(let p) = state { return p }
            if case .failed = state { throw MLXError.startupTimeout }
            if let last = lastProgressAt {
                deadline = min(max(deadline, last.addingTimeInterval(60)), hardDeadline)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw MLXError.startupTimeout
    }

    /// Upper bound for waiting on a start already in flight, regardless of
    /// progress. Generous enough for a large first-run download on a slow line,
    /// short enough that a wedged start eventually reports instead of hanging.
    private static let maximumStartupWait: TimeInterval = 30 * 60
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
