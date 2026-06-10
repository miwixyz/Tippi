import Combine
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

    /// Whether the currently-selected engine can transcribe — gates the
    /// dictation hot key and the popup mic. Whisper needs a downloaded model;
    /// Parakeet self-downloads its CoreML model on first use, so it is always
    /// considered ready (the first dictation triggers the download).
    static var isCurrentEngineReady: Bool {
        switch current {
        case .whisper:  return WhisperConfig.isConfigured
        case .parakeet: return true
        }
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

// MARK: - Parakeet model status (for Settings UI)

/// Observable download/load state of the Parakeet model, so the Settings
/// engine section can show whether Parakeet is actually usable instead of
/// silently downloading 600 MB on the first dictation.
@MainActor
final class ParakeetStatus: ObservableObject {
    static let shared = ParakeetStatus()

    enum Phase: Equatable {
        case notDownloaded
        case downloading(Double)   // fraction 0…1
        case loading               // CoreML compile / load into memory
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .notDownloaded

    /// Syncs the phase with what is on disk. No-op while a download/load is
    /// in flight so live progress isn't clobbered.
    func refreshFromDisk() {
        switch phase {
        case .downloading, .loading:
            return
        default:
            break
        }
        let onDisk = AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory())
        phase = onDisk ? .ready : .notDownloaded
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
                let onDisk = AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory())
                await MainActor.run {
                    ParakeetStatus.shared.phase = onDisk ? .loading : .downloading(0)
                }
                let models = try await AsrModels.downloadAndLoad(
                    version: .v3,
                    progressHandler: { progress in
                        Task { @MainActor in
                            switch progress.phase {
                            case .listing, .downloading:
                                ParakeetStatus.shared.phase = .downloading(progress.fractionCompleted)
                            case .compiling:
                                ParakeetStatus.shared.phase = .loading
                            }
                        }
                    }
                )
                let mgr = AsrManager()
                try await mgr.loadModels(models)
                await MainActor.run { ParakeetStatus.shared.phase = .ready }
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
            await MainActor.run {
                ParakeetStatus.shared.phase = .failed(error.localizedDescription)
            }
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
