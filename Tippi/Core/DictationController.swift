import AppKit

// MARK: - Settings

/// Persisted dictation settings. The feature is off by default and only
/// activatable once a Whisper model is configured (`WhisperConfig.isConfigured`).
@MainActor
enum DictationSettings {
    private static let enabledKey               = "dictation.enabled"
    private static let comboKey                 = "dictation.hotkeyCombo.v1"
    private static let postProcessEnabledKey    = "dictation.postProcess.enabled"
    private static let postProcessPromptKey     = "dictation.postProcess.prompt"
    private static let postProcessProviderKey   = "dictation.postProcess.providerOverride"
    private static let postProcessModelKey      = "dictation.postProcess.modelOverride"

    /// Below this many characters Tippi skips the LLM polish entirely —
    /// short utterances ("ja", "ok", "danke") don't benefit from cleanup
    /// and the round-trip latency dominates user perception.
    static let postProcessMinChars = 20

    /// Default LLM smoothing prompt. Language-agnostic — instructs the model
    /// to keep the source language so a single prompt covers DE/EN/ES/…
    static let defaultPostProcessPrompt = """
    You receive a raw dictation transcript. Clean it up:
    – remove filler words ("um", "uh", "äh", "ähm", "halt", "also", "you know")
    – add punctuation and sensible capitalization
    – fix obvious self-corrections (keep the corrected version, drop the false start)
    – keep the meaning, tone and language exactly as in the input
    – do NOT translate, summarize, or rephrase
    Return ONLY the cleaned text, no preamble, no commentary, no quotes.
    """

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = UserDefaults.standard.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .dictationDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: comboKey)
            }
        }
    }

    /// Post-process the raw Whisper transcript through the active LLM
    /// provider to remove filler words and add punctuation. Default: OFF
    /// (adds 1–3 s latency, opt-in).
    static var postProcessEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: postProcessEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: postProcessEnabledKey) }
    }

    static var postProcessPrompt: String {
        get { UserDefaults.standard.string(forKey: postProcessPromptKey) ?? defaultPostProcessPrompt }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: postProcessPromptKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: postProcessPromptKey)
            }
        }
    }

    /// Optional provider ID override for the polish step. Empty/nil = use
    /// the same provider as everything else (LLMRouter's preferred). Set to
    /// a specific provider ID (e.g. "groq") to always polish through the
    /// fastest available hosted LLM regardless of the chat provider.
    static var postProcessProviderOverride: String {
        get { UserDefaults.standard.string(forKey: postProcessProviderKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: postProcessProviderKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: postProcessProviderKey)
            }
        }
    }

    /// Optional model override for the polish step, paired with the provider
    /// override. Empty = use the provider's `defaultModel`.
    static var postProcessModelOverride: String {
        get { UserDefaults.standard.string(forKey: postProcessModelKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: postProcessModelKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: postProcessModelKey)
            }
        }
    }
}

// MARK: - Controller

/// Dictation-mode state machine. Press the dictation hot key once to start
/// recording, again to stop → transcribe → insert at the caret. No popup is
/// shown, so the source app keeps focus and the caret stays put.
@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(URL)
        case transcribing
    }

    @Published private(set) var state: State = .idle

    private let recorder = AudioRecorder()

    /// Guards against a second hotkey press while `start()` is suspended in
    /// the mic-permission prompt — `state` is still `.idle` at that point, so
    /// the toggle would start a second recording on the same recorder.
    private var isStarting = false

    /// In-flight transcription (transcribe → polish → insert); kept so a
    /// hotkey press during `.transcribing` can cancel it.
    private var transcriptionTask: Task<Void, Never>?

    /// Toggles dictation. `targetApp` is the app that was frontmost when the
    /// hot key fired — used as the AX target for insertion. A press while
    /// transcription is running cancels it.
    func toggle(targetApp: NSRunningApplication?) async {
        switch state {
        case .idle:
            await start()
        case .recording(let url):
            beginTranscription(wavURL: url, targetApp: targetApp)
        case .transcribing:
            NSLog("Tippi: dictation cancel requested")
            transcriptionTask?.cancel()
        }
    }

    // MARK: - Private

    private func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        guard await AudioRecorder.requestPermission() else {
            ToastWindowController.shared.show(message: String(localized: "dictation.toast.micDenied"))
            return
        }
        do {
            let url = try recorder.start()
            state = .recording(url)
            RecordingIndicatorWindowController.shared.show(mode: .recording)
            NSLog("Tippi: dictation recording started")
            // Warm the model's file cache while the user is speaking, so a
            // cold first transcription doesn't stall on loading the model.
            Task.detached(priority: .utility) {
                WhisperTranscriber.prewarmModelCache()
            }
        } catch {
            ToastWindowController.shared.show(message: error.localizedDescription)
            NSLog("Tippi: dictation start failed — \(error.localizedDescription)")
        }
    }

    private func beginTranscription(wavURL: URL, targetApp: NSRunningApplication?) {
        recorder.stop()
        state = .transcribing
        RecordingIndicatorWindowController.shared.show(mode: .transcribing)
        transcriptionTask = Task { [weak self] in
            await self?.transcribeAndInsert(wavURL: wavURL, targetApp: targetApp)
        }
    }

    private func transcribeAndInsert(wavURL: URL, targetApp: NSRunningApplication?) async {
        do {
            let raw = try await WhisperTranscriber.transcribe(wavURL: wavURL)
            try Task.checkCancellation()
            let final = await postProcessIfEnabled(raw)
            try Task.checkCancellation()
            await TextInsertion.replace(with: final, in: targetApp)
            RecordingIndicatorWindowController.shared.hide()
            ToastWindowController.shared.show(message: String(localized: "dictation.toast.inserted"))
            NSLog("Tippi: dictation inserted \(final.count) chars (raw=\(raw.count))")
        } catch {
            RecordingIndicatorWindowController.shared.hide()
            if error is CancellationError || Task.isCancelled {
                ToastWindowController.shared.show(message: String(localized: "dictation.toast.cancelled"))
                NSLog("Tippi: dictation cancelled by user")
            } else {
                ToastWindowController.shared.show(message: error.localizedDescription)
                NSLog("Tippi: dictation transcription failed — \(error.localizedDescription)")
            }
        }

        state = .idle
        transcriptionTask = nil
    }

    /// Run the raw Whisper transcript through the active LLM provider for
    /// filler-word removal and punctuation, if the user has enabled it.
    /// On any failure (no provider, network error, empty input) returns the
    /// raw transcript unchanged so dictation never breaks because of LLM
    /// trouble.
    private func postProcessIfEnabled(_ raw: String) async -> String {
        guard DictationSettings.postProcessEnabled else { return raw }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        // Short-circuit very short utterances ("ja", "ok", "danke") — the
        // LLM round-trip would dominate perceived latency without adding
        // meaningful cleanup.
        guard trimmed.count >= DictationSettings.postProcessMinChars else {
            NSLog("Tippi: dictation post-process skipped — \(trimmed.count) chars < min \(DictationSettings.postProcessMinChars)")
            return raw
        }

        let providerOverride = DictationSettings.postProcessProviderOverride
        let modelOverride    = DictationSettings.postProcessModelOverride

        do {
            // Hard 30s cap: dictation must never hang on the polish step.
            // A local provider cold-starting its server (MLX model load can
            // take minutes) would otherwise leave the user staring at
            // "Transcribing…" — past the cap the raw transcript is inserted.
            let prompt = DictationSettings.postProcessPrompt
            let result: CompletionResult = try await withThrowingTaskGroup(of: CompletionResult.self) { group in
                group.addTask {
                    if !providerOverride.isEmpty {
                        return try await LLMRouter.shared.complete(
                            systemPrompt: prompt,
                            userText: trimmed,
                            forceProviderID: providerOverride,
                            forceModel: modelOverride
                        )
                    } else {
                        return try await LLMRouter.shared.complete(
                            systemPrompt: prompt,
                            userText: trimmed
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw LLMError.cancelled
                }
                guard let first = try await group.next() else { throw LLMError.cancelled }
                group.cancelAll()
                return first
            }
            let polished = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !polished.isEmpty else {
                NSLog("Tippi: dictation post-process returned empty — keeping raw")
                return raw
            }
            NSLog("Tippi: dictation post-processed via \(result.providerDisplay) in \(String(format: "%.2f", result.duration))s")
            do {
                try HistoryStore.shared.append(
                    appName: "Dictation",
                    promptTitle: "Dictation polish",
                    provider: result.providerID,
                    model: result.model,
                    language: nil,
                    latencyMs: Int((result.duration * 1000).rounded()),
                    input: trimmed,
                    output: polished
                )
            } catch {
                NSLog("Tippi: history append failed — \(error.localizedDescription)")
            }
            return polished
        } catch {
            NSLog("Tippi: dictation post-process failed — \(error.localizedDescription) — keeping raw")
            return raw
        }
    }
}
