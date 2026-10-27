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
        // Default: Parakeet v3 — markedly faster and lower WER than Whisper
        // small, stays in memory (no per-dictation cold start), and self-
        // downloads its model on first use. Users who explicitly picked an
        // engine keep their choice (a stored value overrides this default).
        get { Kind(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .parakeet }
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

// MARK: - Parakeet build

/// Which Parakeet build transcribes (2026-10-27). Ultra is Moondream's
/// post-training of Parakeet TDT v3: same architecture, languages, tokenizer
/// and speed, fewer errors in FluidAudio's own benchmarks (FLEURS 24-language
/// mean WER 14.81 % → 11.67 %, release notes of FluidAudio 0.17.3). Not
/// measured on Michael's German yet — that is what
/// `scripts/parakeet-vergleich.sh` is for — so v3 stays the default and Ultra
/// is an opt-in. Both builds live in their own folder under FluidAudio's model
/// cache; switching never deletes the other one (v3 ≈ 470 MB, Ultra ≈ 630 MB).
enum ParakeetModel: String, CaseIterable {
    case v3
    case ultra

    /// `.standard` in the app, a throwaway suite in tests — the test host shares
    /// the installed app's preferences file (see `DictationSettings.store`).
    /// Not MainActor-bound: the transcriber actor reads it before every load.
    static var store: UserDefaults = .standard
    static let key = "voice.parakeetModel.v1"

    static var current: ParakeetModel {
        get { ParakeetModel(rawValue: store.string(forKey: key) ?? "") ?? .v3 }
        set { store.set(newValue.rawValue, forKey: key) }
    }

    var asrVersion: AsrModelVersion {
        switch self {
        case .v3: return .v3
        case .ultra: return .ultra
        }
    }

    /// Proper noun — shown unlocalized (engine picker, dictation toast).
    var displayName: String {
        switch self {
        case .v3: return "Parakeet v3"
        case .ultra: return "Parakeet Ultra"
        }
    }

    var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: asrVersion), version: asrVersion)
    }
}

// MARK: - Facade

/// Engine-agnostic entry point with the same contract as
/// `WhisperTranscriber.transcribe`: consumes the WAV (deleted on every exit
/// path) and returns the transcribed text.
enum SpeechTranscriber {
    /// Both engines return here, and every microphone path (dictation, prompt
    /// popup, translate panel) goes through here — so this is the one place the
    /// user's `Tipi → Tippi` corrections are applied: once, for both engines,
    /// before any AI cleanup, and also when cleanup is off.
    static func transcribe(wavURL: URL) async throws -> String {
        let raw: String
        switch SpeechEngine.current {
        case .whisper:
            raw = try await WhisperTranscriber.transcribe(wavURL: wavURL)
        case .parakeet:
            raw = try await ParakeetTranscriber.shared.transcribe(wavURL: wavURL)
        }
        let entries = await MainActor.run { DictationSettings.customWords }
        return CustomWordVariants.apply(to: raw, entries: entries)
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

    /// Syncs the phase with what is on disk for the selected build. No-op while
    /// a download/load is in flight so live progress isn't clobbered — unless
    /// `force`: after switching builds the old build's progress is not news
    /// about the new one (a load of the new build reports its own phases).
    func refreshFromDisk(force: Bool = false) {
        if !force {
            switch phase {
            case .downloading, .loading:
                return
            default:
                break
            }
        }
        phase = ParakeetModel.current.isDownloaded ? .ready : .notDownloaded
    }

    /// Progress of a load only counts while its build is still the selected
    /// one — a v3 load finishing after the switch to Ultra must not show
    /// "ready" for Ultra.
    func report(_ phase: Phase, for model: ParakeetModel) {
        guard model == ParakeetModel.current else { return }
        self.phase = phase
    }
}

// MARK: - Parakeet (FluidAudio / CoreML)

enum ParakeetError: LocalizedError {
    case noOutput

    var errorDescription: String? {
        switch self {
        case .noOutput: return "Parakeet produced no transcription."
        }
    }
}

actor ParakeetTranscriber {
    static let shared = ParakeetTranscriber()

    /// One build in memory at a time: the one last loaded for the selection.
    private var manager: AsrManager?
    private var managerModel: ParakeetModel?
    /// The load in flight and its build. Actor methods are reentrant at
    /// `await`: without the build tag a switch v3 → Ultra during a slow load
    /// would hand the v3 manager to an Ultra request.
    private var loadTask: Task<AsrManager, Error>?
    private var loadTaskModel: ParakeetModel?

    /// Returns the loaded ASR manager for the selected build, downloading the
    /// CoreML bundle from Hugging Face on first use (v3 ≈ 470 MB, Ultra ≈
    /// 630 MB, cached afterwards) and keeping it in memory. Switching builds
    /// loads the other one on the next request and drops the old one.
    private func loadedManager() async throws -> AsrManager {
        let model = ParakeetModel.current
        if let manager, managerModel == model { return manager }
        let task: Task<AsrManager, Error>
        if let loadTask, loadTaskModel == model {
            task = loadTask
        } else {
            task = Self.makeLoadTask(for: model)
            loadTask = task
            loadTaskModel = model
        }
        do {
            let mgr = try await task.value
            if loadTaskModel == model {
                loadTask = nil
                loadTaskModel = nil
            }
            // Install only while still selected; an outdated build is used for
            // this one request (it was asked for under the old selection) but
            // never replaces the current one.
            if managerModel != model, model == ParakeetModel.current {
                manager = mgr
                managerModel = model
            }
            return mgr
        } catch {
            // Allow a retry on the next attempt (e.g. download failed offline).
            if loadTaskModel == model {
                loadTask = nil
                loadTaskModel = nil
            }
            await MainActor.run {
                ParakeetStatus.shared.report(.failed(error.localizedDescription), for: model)
            }
            throw error
        }
    }

    private static func makeLoadTask(for model: ParakeetModel) -> Task<AsrManager, Error> {
        Task {
            let onDisk = model.isDownloaded
            await MainActor.run {
                ParakeetStatus.shared.report(onDisk ? .loading : .downloading(0), for: model)
            }
            let models = try await AsrModels.downloadAndLoad(
                version: model.asrVersion,
                progressHandler: { progress in
                    Task { @MainActor in
                        switch progress.phase {
                        case .listing, .downloading:
                            ParakeetStatus.shared.report(.downloading(progress.fractionCompleted), for: model)
                        case .compiling:
                            ParakeetStatus.shared.report(.loading, for: model)
                        @unknown default:
                            // Future FluidAudio phases shouldn't break the
                            // build or strand the status — treat as loading.
                            ParakeetStatus.shared.report(.loading, for: model)
                        }
                    }
                }
            )
            // downloadAndLoad finished; the CoreML model still has to be
            // loaded into memory — surface that as a distinct loading state
            // instead of leaving the last download/compile phase showing.
            await MainActor.run { ParakeetStatus.shared.report(.loading, for: model) }
            let mgr = AsrManager()
            try await mgr.loadModels(models)
            await MainActor.run { ParakeetStatus.shared.report(.ready, for: model) }
            return mgr
        }
    }

    func prewarm() async {
        _ = try? await loadedManager()
    }

    /// Whether the selected build is in memory — the live preview waits for
    /// the load instead of counting it as a slow pass.
    var isLoaded: Bool { manager != nil && managerModel == ParakeetModel.current }

    /// Live preview (LiveTranscriptionPreview): transcribes in-memory 16 kHz
    /// mono samples with the same model, decoder setup and language hint as
    /// `transcribe(wavURL:)` — so the preview matches the final text. Nothing
    /// touches the disk. Throws for audio shorter than the model's minimum
    /// (the preview only calls it from 1 s of audio on).
    func transcribe(samples: [Float]) async throws -> String {
        let manager = try await loadedManager()
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState,
                                                  language: Language(rawValue: WhisperConfig.language))
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(wavURL: URL) async throws -> String {
        // Same privacy contract as WhisperTranscriber: the recording must
        // not outlive the transcription attempt.
        defer { try? FileManager.default.removeItem(at: wavURL) }

        // Honour user cancellation at the points we control. The CoreML/ANE
        // inference itself runs in-process and can't be killed mid-flight like
        // the whisper-cli subprocess, but bailing before model load and before
        // returning keeps a cancelled dictation from inserting stale text.
        try Task.checkCancellation()
        let manager = try await loadedManager()
        try Task.checkCancellation()

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // Reuse the Whisper language setting as a script hint; "auto" or
        // unsupported codes fall back to Parakeet's own detection.
        let languageHint = Language(rawValue: WhisperConfig.language)
        let result = try await manager.transcribe(
            wavURL,
            decoderState: &decoderState,
            language: languageHint
        )
        try Task.checkCancellation()

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ParakeetError.noOutput }
        return text
    }
}
