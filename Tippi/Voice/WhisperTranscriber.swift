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
    /// Runs whisper-cli on `wavURL` and returns the transcribed text.
    /// The WAV file is cleaned up on completion; the caller owns it until then.
    static func transcribe(wavURL: URL) async throws -> String {
        let binary    = WhisperConfig.binaryPath
        let modelPath = WhisperConfig.modelPath
        let language  = WhisperConfig.language

        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw WhisperError.binaryNotFound
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound
        }

        // whisper-cli --output-txt writes a sidecar <name>.wav.txt (appends .txt to
        // the full input filename, it does NOT strip the .wav extension first).
        let txtURL = wavURL.appendingPathExtension("txt")

        // Run the process and wait for it to finish.
        try await runProcess(
            binary: binary,
            arguments: [
                "--model",    modelPath,
                "--language", language,
                "--output-txt",
                "--file",     wavURL.path,
            ]
        )

        // Read sidecar file.
        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: txtURL)
        }

        let text = (try? String(contentsOf: txtURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else { throw WhisperError.noOutput }
        return text
    }

    // MARK: - Private

    private static func runProcess(binary: String, arguments: [String]) async throws {
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
    private var errorData = Data()
    var process: Process?

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
        let proc = process
        lock.unlock()
        if proc?.isRunning == true {
            proc?.terminate()
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
