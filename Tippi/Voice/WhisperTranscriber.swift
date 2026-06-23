import Foundation

// MARK: - Errors

enum WhisperError: LocalizedError {
    case binaryNotFound
    case modelNotFound
    case processFailed(String)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return String(localized: "voice.error.noBinary")
        case .modelNotFound:
            return String(localized: "voice.error.noModel")
        case .processFailed(let msg):
            return "Whisper failed: \(msg)"
        case .noOutput:
            return "No speech detected."
        }
    }
}

// MARK: - Config

/// Persisted via UserDefaults. `isConfigured` is the single gate for enabling the feature.
enum WhisperConfig {
    private static let binaryKey = "voice.whisperBinaryPath"
    private static let modelKey  = "voice.whisperModelPath"
    private static let langKey   = "voice.language"

    // MARK: Binary resolution

    /// In release builds: whisper-cli bundled at Contents/MacOS/ alongside the main exe.
    static var bundledBinaryPath: String? {
        guard let url = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("whisper-cli")
        else { return nil }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }

    /// Homebrew fall-backs for development builds (Xcode, `make build`).
    static let brewBinaryPaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper",
    ]

    static var autoDetectedBinaryPath: String? {
        bundledBinaryPath
            ?? brewBinaryPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Resolved binary: user override → bundled → Homebrew → empty.
    static var binaryPath: String {
        get {
            let stored = UserDefaults.standard.string(forKey: binaryKey) ?? ""
            return stored.isEmpty ? (autoDetectedBinaryPath ?? "") : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: binaryKey) }
    }

    // MARK: Model resolution

    /// App-managed model storage: ~/Library/Application Support/com.tippi.app/Models/
    static var appModelDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("com.tippi.app/Models", isDirectory: true)
    }

    /// Best available model: first app-support model, then ~/.cache/whisper/ (Homebrew default).
    static var autoDetectedModelPath: String? {
        let fm = FileManager.default
        // Check app support directory first
        if let url = try? fm.contentsOfDirectory(at: appModelDirectory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "bin" }) {
            return url.path
        }
        // Homebrew / manual cache fall-back
        let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/whisper")
        if let url = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "bin" }) {
            return url.path
        }
        return nil
    }

    static var modelPath: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? ""
            return stored.isEmpty ? (autoDetectedModelPath ?? "") : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// Whisper language code, e.g. "auto", "en", "de". Defaults to "auto".
    static var language: String {
        get { UserDefaults.standard.string(forKey: langKey) ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: langKey) }
    }

    static var isConfigured: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath) &&
        FileManager.default.fileExists(atPath: modelPath)
    }
}

// MARK: - Transcriber

struct WhisperTranscriber {
    /// Path the cache was last warmed for — skip re-reading the same 0.5 GB
    /// file on every recording start once it's already in the OS cache.
    private static let prewarmLock = NSLock()
    nonisolated(unsafe) private static var lastPrewarmedPath: String?

    /// Reads the model file once so it sits in the OS file cache before
    /// whisper-cli (a fresh process per transcription) loads it. A cold load
    /// of the ~0.5 GB model otherwise adds many seconds to the first
    /// dictation — calling this while the user is still speaking hides it.
    /// Skips the (re-)read when the same model was already warmed this session.
    static func prewarmModelCache() {
        let path = WhisperConfig.modelPath
        guard !path.isEmpty else { return }

        prewarmLock.lock()
        let alreadyWarmed = (lastPrewarmedPath == path)
        prewarmLock.unlock()
        guard !alreadyWarmed else { return }

        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            _ = chunk
        }
        prewarmLock.lock()
        lastPrewarmedPath = path
        prewarmLock.unlock()
    }

    /// Runs whisper-cli on `wavURL` and returns the transcribed text.
    /// The WAV file is cleaned up on completion; the caller owns it until then.
    static func transcribe(wavURL: URL) async throws -> String {
        // whisper-cli --output-txt writes a sidecar <name>.wav.txt (appends .txt to
        // the full input filename, it does NOT strip the .wav extension first).
        let txtURL = wavURL.appendingPathExtension("txt")

        // The WAV contains the user's voice — it must be removed on EVERY exit
        // path, including the guards and a process failure below.
        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: txtURL)
        }

        let binary    = WhisperConfig.binaryPath
        let modelPath = WhisperConfig.modelPath
        let language  = WhisperConfig.language

        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw WhisperError.binaryNotFound
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound
        }

        // Run the process and wait for it to finish.
        // --flash-attn is mathematically exact (no quality change) and ~15%
        // faster on Metal.
        try await runProcess(
            binary: binary,
            arguments: [
                "--model",    modelPath,
                "--language", language,
                "--flash-attn",
                "--output-txt",
                "--file",     wavURL.path,
            ]
        )

        // Read sidecar file.
        let text = (try? String(contentsOf: txtURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else { throw WhisperError.noOutput }
        return text
    }

    // MARK: - Private

    private static func runProcess(binary: String, arguments: [String]) async throws {
        // Bail out before spawning whisper-cli if the caller already cancelled.
        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await runProcessUntilExit(binary: binary, arguments: arguments)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 120_000_000_000)
                throw WhisperError.processFailed("Timed out after 120 seconds.")
            }

            guard let result = try await group.next() else { return }
            group.cancelAll()
            return result
        }
    }

    private static func runProcessUntilExit(binary: String, arguments: [String]) async throws {
        let runner = ProcessRunner()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice

                let errPipe = Pipe()
                process.standardError = errPipe
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    runner.appendError(handle.availableData)
                }

                runner.process = process
                process.terminationHandler = { proc in
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    if proc.terminationStatus == 0 {
                        runner.resume(cont)
                    } else {
                        let msg = runner.errorMessage(fallback: "exit \(proc.terminationStatus)")
                        runner.resume(cont, throwing: WhisperError.processFailed(msg))
                    }
                }

                // Close the cancel-vs-run race: if `onCancel` already fired
                // before the process was stored, don't launch an orphan that
                // would keep running (Metal/CPU) after the user cancelled.
                guard !runner.registerStartIfNotCancelled() else {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    runner.resume(cont, throwing: CancellationError())
                    return
                }

                do {
                    try process.run()
                } catch {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    runner.resume(cont, throwing: WhisperError.processFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            runner.terminate()
        }
    }
}

private final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private var cancelRequested = false
    private var errorData = Data()
    var process: Process?

    /// Returns `true` if cancellation already happened (caller should abort the
    /// launch instead of spawning an orphan process).
    func registerStartIfNotCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelRequested
    }

    func appendError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        if errorData.count < 16_384 {
            errorData.append(data.prefix(16_384 - errorData.count))
        }
        lock.unlock()
    }

    func errorMessage(fallback: String) -> String {
        lock.lock()
        let data = errorData
        lock.unlock()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? fallback : message
    }

    func terminate() {
        lock.lock()
        cancelRequested = true
        let proc = process
        lock.unlock()
        guard let proc, proc.isRunning else { return }
        proc.terminate()
        // whisper-cli can ignore SIGTERM (e.g. stuck in a Metal call), which
        // would leave the caller waiting forever despite the timeout — escalate.
        let pid = proc.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if proc.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    func resume(_ continuation: CheckedContinuation<Void, Error>, throwing error: Error? = nil) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
