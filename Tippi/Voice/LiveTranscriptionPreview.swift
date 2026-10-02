import Foundation

/// Live text in the dictation recording window (2026-10-02).
///
/// How: while the take runs, transcribe *everything recorded so far* with the
/// same Parakeet batch path the final result uses, about once per second, and
/// show it. Measured in docs/spikes/2026-10-02-live-diktat/ (Mac mini M2 Pro):
/// first text ~2 s after speech starts, preview quality = final quality, and
/// on release the inserted text matches the last preview (0 % jump on a real
/// dictation) — because it is the same model and the same method. FluidAudio's
/// `SlidingWindowAsrManager` was measured and rejected (13.8 s to first text,
/// or 29–280 % word errors with small windows).
///
/// Off by default (Settings → Voice → Dictation): it costs one transcription
/// pass per second, which weaker Macs may not want. Parakeet only — Whisper
/// runs as a subprocess per file and can't do this cheaply.
@MainActor
final class LiveTranscriptionPreview: ObservableObject {
    @Published private(set) var text: String = ""

    private var task: Task<Void, Never>?

    /// Whether a new dictation should get a live preview.
    static var isActive: Bool {
        DictationSettings.livePreviewEnabled && SpeechEngine.current == .parakeet
    }

    func start(recorder: AudioRecorder) {
        task?.cancel()
        text = ""
        // The recorder is shared: if the popup or translate panel takes it over
        // mid-dictation, its audio must not show up in the dictation window.
        let owner = recorder.owner
        task = Task { [weak self] in
            var interval: TimeInterval = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, recorder.isRecording, recorder.owner == owner else { return }
                // Engine switched to Whisper mid-take: the inserted text will come
                // from Whisper, a Parakeet preview would only mislead.
                guard SpeechEngine.current == .parakeet else { self?.text = ""; return }
                // First dictation after launch: the model is still loading. Wait for
                // that load (shared with prewarm, no second download) instead of
                // counting it as a slow pass, which stretched the interval to 2× the
                // load time. If it can't load (offline, broken cache), give up for
                // this take — the final transcription reports the error.
                let loaded = await ParakeetTranscriber.shared.isLoaded
                if !loaded {
                    await ParakeetTranscriber.shared.prewarm()
                    let nowLoaded = await ParakeetTranscriber.shared.isLoaded
                    guard nowLoaded else { return }
                    continue
                }
                let samples = recorder.snapshot()
                guard samples.count >= Int(AudioCapture.sampleRate) else { continue }   // < 1 s: nothing to read yet
                let started = Date()
                let raw = try? await ParakeetTranscriber.shared.transcribe(samples: samples)
                interval = Self.nextInterval(afterPassTaking: Date().timeIntervalSince(started))
                // The take may have ended while this pass ran — don't paint stale text over the next phase.
                guard !Task.isCancelled, recorder.isRecording, recorder.owner == owner, let self else { return }
                guard let raw else { continue }
                // Same custom-word fixes as the final text, or the preview would jump on release.
                self.text = CustomWordVariants.apply(to: raw, entries: DictationSettings.customWords)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Re-transcribing everything costs more the longer the take. Keep at least
    /// 1 s between passes, and stretch the pause when a pass gets slow
    /// (long dictation, weaker Mac) so the preview never saturates the machine.
    nonisolated static func nextInterval(afterPassTaking seconds: TimeInterval) -> TimeInterval {
        max(1, seconds * 2)
    }

    /// The window shows the end of the text — what is being said right now.
    nonisolated static func tail(_ text: String, maxCharacters: Int = 180) -> String {
        guard text.count > maxCharacters else { return text }
        let cut = text.suffix(maxCharacters)
        // Start at a word boundary, not mid-word.
        let start = cut.firstIndex(of: " ").map { cut.index(after: $0) } ?? cut.startIndex
        return "…" + cut[start...]
    }
}

/// Text size of the live preview — readable from across the desk (Michael
/// 2026-10-02: „auf die Entfernung kann man das sehr schlecht ausmachen“).
/// The window grows with it so three lines still fit; bigger text shows a
/// shorter tail of what was said.
enum LiveTextSize: String, CaseIterable {
    case normal, large, extraLarge

    var pointSize: CGFloat {
        switch self {
        case .normal: return 13
        case .large: return 17
        case .extraLarge: return 22
        }
    }
    var windowSize: NSSize {
        switch self {
        case .normal: return NSSize(width: 480, height: 150)
        case .large: return NSSize(width: 580, height: 185)
        case .extraLarge: return NSSize(width: 720, height: 235)
        }
    }
    var tailCharacters: Int {
        switch self {
        case .normal: return 180
        case .large: return 150
        case .extraLarge: return 130
        }
    }
}

extension DictationSettings {
    private static let livePreviewKey = "dictation.livePreview.enabled.v1"
    private static let liveTextSizeKey = "dictation.livePreview.textSize.v1"

    static var liveTextSize: LiveTextSize {
        get { LiveTextSize(rawValue: store.string(forKey: liveTextSizeKey) ?? "") ?? .normal }
        set { store.set(newValue.rawValue, forKey: liveTextSizeKey) }
    }

    /// Live text in the recording window while dictating (Parakeet only).
    /// Default OFF: one transcription pass per second — weaker Macs may not
    /// want that (Michael 2026-10-02).
    static var livePreviewEnabled: Bool {
        get { store.bool(forKey: livePreviewKey) }
        set { store.set(newValue, forKey: livePreviewKey) }
    }
}
