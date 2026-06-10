import Foundation
import FluidAudio

// MARK: - Engine selection

/// Which local ASR engine transcribes dictation audio. Whisper (bundled
/// whisper-cli subprocess) remains the default; Parakeet TDT v3 via
/// FluidAudio/CoreML is the spike candidate — ~2× lower German WER than
/// whisper small and runs in-process on the ANE, so the model stays loaded
/// across utterances (no per-transcription cold start).
enum SpeechEngine {
    private static let key = "voice.engine"

    enum Kind: String {
        case whisper
        case parakeet
    }

    static var current: Kind {
        get { Kind(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .whisper }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Facade

/// Engine-agnostic entry point with the same contract as
/// `WhisperTranscriber.transcribe`: consumes the WAV (deleted on every exit
/// path) and returns the transcribed text.
enum SpeechTranscriber {
    static func transcribe(wavURL: URL) async throws -> String {
        switch SpeechEngine.current {
        case .whisper:
            return try await WhisperTranscriber.transcribe(wavURL: wavURL)
        case .parakeet:
            return try await ParakeetTranscriber.shared.transcribe(wavURL: wavURL)
        }
    }

    /// Called when recording starts, so model loading overlaps with the
    /// user speaking instead of delaying the transcription afterwards.
    static func prewarm() {
        Task.detached(priority: .utility) {
            switch SpeechEngine.current {
            case .whisper:
                WhisperTranscriber.prewarmModelCache()
            case .parakeet:
                await ParakeetTranscriber.shared.prewarm()
            }
        }
    }
}

// MARK: - Parakeet (FluidAudio / CoreML)

actor ParakeetTranscriber {
    static let shared = ParakeetTranscriber()

    private var manager: AsrManager?
    private var loadTask: Task<AsrManager, Error>?

    /// Returns the loaded ASR manager, downloading the CoreML bundle from
    /// Hugging Face on first use (~600 MB, cached afterwards) and keeping
    /// the model in memory for the app's lifetime.
    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        if loadTask == nil {
            loadTask = Task {
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                let mgr = AsrManager()
                try await mgr.loadModels(models)
                return mgr
            }
        }
        do {
            let mgr = try await loadTask!.value
            manager = mgr
            return mgr
        } catch {
            // Allow a retry on the next attempt (e.g. download failed offline).
            loadTask = nil
            throw error
        }
    }

    func prewarm() async {
        _ = try? await loadedManager()
    }

    func transcribe(wavURL: URL) async throws -> String {
        // Same privacy contract as WhisperTranscriber: the recording must
        // not outlive the transcription attempt.
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let manager = try await loadedManager()
        var decoderState = TdtDecoderState.make()
        // Reuse the Whisper language setting as a script hint; "auto" or
        // unsupported codes fall back to Parakeet's own detection.
        let languageHint = Language(rawValue: WhisperConfig.language)
        let result = try await manager.transcribe(
            wavURL,
            decoderState: &decoderState,
            language: languageHint
        )

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WhisperError.noOutput }
        return text
    }
}
