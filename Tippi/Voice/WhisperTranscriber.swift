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

    static let knownBinaryPaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper",
        "/usr/local/bin/whisper",
    ]

    static var autoDetectedBinaryPath: String? {
        knownBinaryPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var binaryPath: String {
        get { UserDefaults.standard.string(forKey: binaryKey) ?? autoDetectedBinaryPath ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: binaryKey) }
    }

    /// Default: `~/.cache/whisper/ggml-base.en.bin` (whisper.cpp standard location).
    static var modelPath: String {
        get {
            UserDefaults.standard.string(forKey: modelKey)
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".cache/whisper/ggml-base.en.bin").path
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

        // whisper-cli --output-txt writes a sidecar <name>.txt next to the WAV.
        let txtURL = wavURL.deletingPathExtension().appendingPathExtension("txt")

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
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments     = arguments

            let errPipe = Pipe()
            process.standardOutput = Pipe()  // discard progress chatter
            process.standardError  = errPipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let msg = String(
                        data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? "exit \(proc.terminationStatus)"
                    cont.resume(throwing: WhisperError.processFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                cont.resume(throwing: WhisperError.processFailed(error.localizedDescription))
            }
        }
    }
}
