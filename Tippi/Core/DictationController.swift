import AppKit

// MARK: - Settings

/// Persisted dictation settings. The feature is off by default and only
/// activatable once a Whisper model is configured (`WhisperConfig.isConfigured`).
@MainActor
enum DictationSettings {
    /// Where every setting in here is read and written. Always `.standard` in the
    /// app. Tests swap in a throwaway suite: the test host IS the installed app
    /// (same bundle ID, same preferences file), so a test writing `.standard`
    /// overwrote the user's real settings. Real case, 2026-09-25: after every
    /// update Michael had to set the dictation mode back to "single key" —
    /// `DictationInputModeTests` deleted it on every `make test` before a release.
    static var store: UserDefaults = .standard

    private static let enabledKey               = "dictation.enabled"
    private static let comboKey                 = "dictation.hotkeyCombo.v1"
    private static let postProcessEnabledKey    = "dictation.postProcess.enabled"
    private static let postProcessPromptKey     = "dictation.postProcess.prompt"
    private static let customWordsKey           = "dictation.customWords.v1"
    private static let postProcessProviderKey   = "dictation.postProcess.providerOverride"
    private static let postProcessModelKey      = "dictation.postProcess.modelOverride"
    private static let modeKey                   = "dictation.inputMode.v1"
    private static let tapOrHoldModifierKey      = "dictation.tapOrHold.modifier.v1"
    private static let indicatorPositionKey      = "dictation.indicator.position.v1"

    /// Below this many characters Tippi skips the LLM polish entirely —
    /// short utterances ("ja", "ok", "Hallo, wie geht's?") don't benefit
    /// from cleanup and the round-trip latency dominates user perception.
    /// Raised from 20 → 50 in 2026-06: weak local models (llama3.2:3B etc.)
    /// tend to misinterpret short inputs as conversational prompts and
    /// reply instead of cleaning the text.
    static let postProcessMinChars = 50

    /// Default LLM smoothing prompt. Language-agnostic — instructs the model
    /// to keep the source language so a single prompt covers DE/EN/ES/FR/JA
    /// (matches the dictation language picker's options).
    ///
    /// Hardened against weak instruction-followers (e.g. llama3.2:3B) which
    /// otherwise reply conversationally to short inputs. Includes role lock,
    /// repeated "no commentary" rule, and 7 few-shot examples covering
    /// filler removal, German noun capitalization, hesitation repeats, and
    /// self-correction — plus a guard example for words that are filler in
    /// one language but meaningful in another (English "also").
    static let defaultPostProcessPrompt = """
    You are a text cleanup tool. Your ONLY job is to clean up a raw dictation transcript and return the cleaned text. You are NOT a chatbot. You NEVER respond conversationally. You NEVER ask questions. You NEVER add explanations or preamble.

    Rules:
    1. Remove filler words for whatever language the input is in — German: "um", "äh", "ähm", "halt", "irgendwie", "sozusagen", filler-"also"; English: "um", "uh", "like", filler-"you know"; Spanish: "eh", "este", "o sea", "pues"; French: "euh", "du coup"; Japanese: "あの", "えっと". Never remove a word just because it matches this list if it carries real meaning in context — e.g. English "also" meaning "in addition" ("I also need the file") must stay; only the hesitation use is filler.
    2. Add punctuation and sensible capitalization. In German, capitalize every noun (Substantive), not just sentence starts and proper nouns — standard German orthography, not optional styling.
    3. Remove immediate word/phrase repetitions caused by hesitation (e.g. "the the meeting" → "the meeting", "ich ich wollte" → "ich wollte").
    4. Fix obvious self-corrections — keep the corrected version, drop the false start — only when the speaker clearly abandoned the earlier part ("nein", "no wait", "I mean", "sorry"). If both parts could be intentional (e.g. comparing two options), keep both.
    5. Keep meaning, tone and language EXACTLY as in the input — same language in, same language out
    6. DO NOT translate, summarize, rephrase, expand, or comment
    7. If the input is already clean, return it verbatim
    8. If the input is a greeting or short statement, return it cleaned — do NOT respond to it

    Examples:

    Input: hallo wie gehts dir
    Output: Hallo, wie geht's dir?

    Input: ich brauche äh halt noch zwei Stunden
    Output: Ich brauche noch zwei Stunden.

    Input: das war ähm nein das war gestern
    Output: Das war gestern.

    Input: hello world how are you
    Output: Hello world, how are you?

    Input: um can you send me the file
    Output: Can you send me the file?

    Input: ich brauche die die datei bis morgen
    Output: Ich brauche die Datei bis morgen.

    Input: can you send the report and also the invoice
    Output: Can you send the report and also the invoice?

    Now clean the following transcript. Return ONLY the cleaned text on a single line or in natural paragraphs — nothing else, no quotes, no preamble.
    """

    static var isEnabled: Bool {
        get { store.bool(forKey: enabledKey) }
        set { store.set(newValue, forKey: enabledKey) }
    }

    /// How the dictation hot key behaves.
    enum InputMode: String, CaseIterable, Identifiable {
        /// Classic key combination, one press toggles recording. Stays the
        /// default so existing installs keep the hot key they configured.
        case combo
        /// One modifier key: a short tap toggles, holding records while held.
        case tapOrHold
        var id: String { rawValue }
    }

    /// Separates a tap from a hold. Raised from 250 to 400 ms when the toggle
    /// became a double tap: at 250 ms the first of the two taps was already read
    /// as a hold and started a recording nobody asked for. A deliberate tap runs
    /// 100–300 ms, so 400 leaves room without feeling sluggish.
    static let holdThresholdMs = 400

    /// Safety limit for the hold gesture. A physically stuck key — or a release
    /// event lost because another app grabbed the tap — would otherwise record
    /// forever and quietly fill the disk.
    static let maxHoldSeconds: TimeInterval = 300

    /// Where the recording indicator sits. Bottom is the historical position.
    enum IndicatorPosition: String, CaseIterable, Identifiable {
        case bottom
        case top
        var id: String { rawValue }
    }

    static var indicatorPosition: IndicatorPosition {
        get {
            guard let raw = store.string(forKey: indicatorPositionKey),
                  let pos = IndicatorPosition(rawValue: raw) else { return .bottom }
            return pos
        }
        set { store.set(newValue.rawValue, forKey: indicatorPositionKey) }
    }

    static var mode: InputMode {
        get {
            guard let raw = store.string(forKey: modeKey),
                  let mode = InputMode(rawValue: raw) else { return .combo }
            return mode
        }
        set { store.set(newValue.rawValue, forKey: modeKey) }
    }

    static var tapOrHoldModifier: ModifierKey {
        get {
            guard let raw = store.string(forKey: tapOrHoldModifierKey),
                  let mod = ModifierKey(rawValue: raw) else { return .rightShift }
            return mod
        }
        set { store.set(newValue.rawValue, forKey: tapOrHoldModifierKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = store.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .dictationDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: comboKey)
            }
        }
    }

    /// Post-process the raw Whisper transcript through the active LLM
    /// provider to remove filler words and add punctuation. Default: OFF
    /// (adds 1–3 s latency, opt-in).
    static var postProcessEnabled: Bool {
        get { store.bool(forKey: postProcessEnabledKey) }
        set { store.set(newValue, forKey: postProcessEnabledKey) }
    }

    /// User-supplied terms that transcription reliably gets wrong: brand names,
    /// product names, people, jargon. Stored as plain strings in the exact
    /// spelling the user wants to see.
    ///
    /// Measured need, not a guess: on 2026-09-15 every polish model tested
    /// returned "CineWeb" for "CINEWEB" and one also flattened "CineSocial" to
    /// "Cinesocial". Both had heard the word correctly — they normalised the
    /// capitalisation to what looks like a normal compound word. No model
    /// choice fixes that, because the model has no way to know the house
    /// spelling. It has to be told.
    ///
    /// An entry may also read `Tipi → Tippi` (heard → intended); those are
    /// replaced deterministically after transcription — see
    /// `CustomWordVariants`.
    static var customWords: [String] {
        get { store.stringArray(forKey: customWordsKey) ?? [] }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            store.set(cleaned, forKey: customWordsKey)
        }
    }

    /// The system prompt actually sent for a polish run: the configured prompt
    /// plus a glossary of `customWords`, if any.
    ///
    /// Appended at call time rather than baked into the stored prompt, for two
    /// reasons. A user who edits the prompt (or resets it) keeps the glossary
    /// either way, and the word list stays a list — editable as data in
    /// Settings instead of as prose somebody has to hand-maintain inside a
    /// prompt.
    ///
    /// Deliberately phrased as a spelling constraint, not as a correction
    /// instruction: telling a small model to "fix similar-sounding words"
    /// invites it to rewrite words that were already right. The rule here only
    /// bites when the term is actually present.
    ///
    /// `Tipi → Tippi` entries contribute only their target: the variant was
    /// already replaced deterministically right after transcription
    /// (`SpeechTranscriber.transcribe`), and naming it here would invite the
    /// model to guess — see `CustomWordVariants`.
    static var effectivePostProcessPrompt: String {
        promptWithGlossary(postProcessPrompt, customWords: customWords)
    }

    /// Pure half of `effectivePostProcessPrompt`, testable without touching
    /// the real preferences.
    static func promptWithGlossary(_ base: String, customWords: [String]) -> String {
        let words = CustomWordVariants.glossaryTerms(from: customWords)
        guard !words.isEmpty else { return base }
        let list = words.joined(separator: ", ")
        return base + """


        Spelling: these terms have a fixed spelling and must appear exactly as written here whenever they occur — \(list). Correct only the spelling or capitalisation of these specific terms; never insert them, and never alter any other word to resemble them.
        """
    }

    static var postProcessPrompt: String {
        get { store.string(forKey: postProcessPromptKey) ?? defaultPostProcessPrompt }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                store.removeObject(forKey: postProcessPromptKey)
            } else {
                store.set(newValue, forKey: postProcessPromptKey)
            }
        }
    }

    /// Optional provider ID override for the polish step. Empty/nil = use
    /// the same provider as everything else (LLMRouter's preferred). Set to
    /// a specific provider ID (e.g. "groq") to always polish through the
    /// fastest available hosted LLM regardless of the chat provider.
    static var postProcessProviderOverride: String {
        get { store.string(forKey: postProcessProviderKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                store.removeObject(forKey: postProcessProviderKey)
            } else {
                store.set(trimmed, forKey: postProcessProviderKey)
            }
        }
    }

    /// Optional model override for the polish step, paired with the provider
    /// override. Empty = use the provider's `defaultModel`.
    static var postProcessModelOverride: String {
        get { store.string(forKey: postProcessModelKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                store.removeObject(forKey: postProcessModelKey)
            } else {
                store.set(trimmed, forKey: postProcessModelKey)
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

    private let recorder: AudioRecorder

    /// Inject the shared `AudioRecorder` so dictation and the popup mic never
    /// run two recorders against the same audio hardware/temp file.
    init(recorder: AudioRecorder) {
        self.recorder = recorder
    }

    /// Guards against a second hotkey press while `start()` is suspended in
    /// the mic-permission prompt — `state` is still `.idle` at that point, so
    /// the toggle would start a second recording on the same recorder.
    private var isStarting = false

    /// In-flight transcription (transcribe → polish → insert); kept so a
    /// hotkey press during `.transcribing` can cancel it.
    private var transcriptionTask: Task<Void, Never>?

    /// Stops a hold that never got a release event (stuck key, or the release
    /// swallowed while another app owned the event tap). Without this, "record
    /// while held" can mean "record until the disk is full".
    private var holdWatchdog: Timer?

    /// Toggles dictation. `targetApp` is the app that was frontmost when the
    /// hot key fired — used as the AX target for insertion. A press while
    /// transcription is running cancels it.
    func toggle(targetApp: NSRunningApplication?, notesTextView: NSTextView? = nil) async {
        switch state {
        case .idle:
            await start()
        case .recording(let url):
            beginTranscription(wavURL: url, targetApp: targetApp, notesTextView: notesTextView)
        case .transcribing:
            NSLog("Tippi: dictation cancel requested")
            transcriptionTask?.cancel()
        }
    }

    /// Starts recording for the hold gesture. Deliberately a no-op unless idle:
    /// a duplicate `.holdBegan` must never stack a second recorder onto the same
    /// audio hardware.
    func beginHoldRecording() async {
        guard case .idle = state else { return }
        await start()
        // Only arm the watchdog if recording actually began — `start()` returns
        // without recording when the mic permission is denied.
        guard case .recording = state else { return }
        holdWatchdog?.invalidate()
        holdWatchdog = Timer.scheduledTimer(
            withTimeInterval: DictationSettings.maxHoldSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .recording(let url) = self.state else { return }
                NSLog("Tippi: dictation hold exceeded \(Int(DictationSettings.maxHoldSeconds))s — stopping (stuck key?)")
                ToastWindowController.shared.show(message: String(localized: "dictation.toast.holdTimeout"))
                self.beginTranscription(wavURL: url, targetApp: nil)
            }
        }
    }

    /// Ends the hold gesture and transcribes. No-op unless recording, so a
    /// release without a matching press cannot fire anything.
    func endHoldRecording(targetApp: NSRunningApplication?, notesTextView: NSTextView? = nil) {
        guard case .recording(let url) = state else {
            holdWatchdog?.invalidate()
            holdWatchdog = nil
            return
        }
        beginTranscription(wavURL: url, targetApp: targetApp, notesTextView: notesTextView)
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
            RecordingIndicatorWindowController.shared.show(
                mode: .recording,
                recorder: recorder,
                aiEnabled: DictationSettings.postProcessEnabled
            )
            NSLog("Tippi: dictation recording started")
            // Warm the engine while the user is speaking, so a cold first
            // transcription doesn't stall on loading the model.
            SpeechTranscriber.prewarm()
            // Same idea for the polish step: if it resolves to the local MLX
            // provider, warm that server now too — otherwise MLXServerManager
            // only auto-starts at app launch when MLX is the GLOBAL default
            // provider (MLXServerManager.autoStartIfPreferred). A dictation-only
            // override to MLX (global default set to a cloud provider) meant the
            // server never started until the first real polish request, paying
            // the full cold-start cost (process launch + weight load + Metal
            // kernel compile) AFTER transcription already finished — squarely in
            // the perceived-latency path. Mirrors WhisperBar's "model loads
            // while you are still speaking" fix (changelog v1.16.0/v1.17.0).
            warmPostProcessProviderIfNeeded()
        } catch {
            ToastWindowController.shared.show(message: error.localizedDescription)
            NSLog("Tippi: dictation start failed — \(error.localizedDescription)")
        }
    }

    private func beginTranscription(wavURL: URL, targetApp: NSRunningApplication?, notesTextView: NSTextView? = nil) {
        // Central exit from `.recording` — covers tap-toggle, hold release and watchdog.
        holdWatchdog?.invalidate()
        holdWatchdog = nil
        recorder.stop()
        state = .transcribing
        RecordingIndicatorWindowController.shared.show(
            mode: .transcribing,
            recorder: recorder,
            aiEnabled: DictationSettings.postProcessEnabled
        )
        transcriptionTask = Task { [weak self] in
            await self?.transcribeAndInsert(wavURL: wavURL, targetApp: targetApp, notesTextView: notesTextView)
        }
    }

    /// `notesTextView`: Tippi's own Notes editor had focus when the hotkey fired.
    /// The text goes in there natively — before, dictation always targeted the
    /// last *other* app and wrote into its focused field in the background
    /// (audit 2026-09-27; trigger and translate already handled Notes).
    private func transcribeAndInsert(wavURL: URL, targetApp: NSRunningApplication?, notesTextView: NSTextView? = nil) async {
        do {
            let raw = try await SpeechTranscriber.transcribe(wavURL: wavURL)
            try Task.checkCancellation()
            let (final, cleanupNotice) = await postProcessIfEnabled(raw)
            try Task.checkCancellation()
            // Decided BEFORE insertion: the clipboard fallback activates the target
            // app itself, so "frontmost" afterwards is true by construction.
            let returnDecision = DictationSettings.autoReturnDecision(
                raw: raw,
                inserted: final,
                // Notes is Tippi's own editor: never a Return target.
                targetBundleID: notesTextView == nil ? targetApp?.bundleIdentifier : nil,
                frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                allowed: DictationSettings.autoReturnBundleIDs
            )
            // Shielded from cancellation: the hotkey cancels `transcriptionTask`
            // while the state is still `.transcribing`, and a cancelled task's
            // `try? Task.sleep` returns at once — the clipboard was restored
            // before the app read ⌘V, so the user's OLD clipboard got pasted
            // (audit 2026-09-27). An unstructured Task does not inherit the
            // cancellation, so the insertion always runs to completion.
            // Withholding the synthetic Return is not enough in a terminal: a line
            // break in the text acts as one without bracketed paste. So in a
            // command-capable app on the Return list, text always goes in as a
            // single line (Rafter 2026-09-27). Chat apps keep their paragraphs.
            let isCommandTarget = targetApp?.bundleIdentifier.map(DictationSettings.commandCapableBundleIDs.contains) ?? false
            let textToInsert = (returnDecision != .skip && isCommandTarget) ? Self.singleLine(final) : final
            let copiedInstead = await Task { @MainActor () -> Bool in
                if let notesTextView {
                    // The Notes window is kept (not released) when closed, so
                    // `window != nil` proves nothing — visibility does. Closed
                    // meanwhile: clipboard, never a background app.
                    guard notesTextView.window?.isVisible == true else {
                        TextInsertion.copy(textToInsert)
                        return true
                    }
                    ReplacementWriter.writeNative(textToInsert, in: notesTextView, range: notesTextView.selectedRange())
                } else {
                    await TextInsertion.replace(with: textToInsert, in: targetApp)
                }
                return false
            }.value
            var pressReturn = false
            // A cancel that arrived during insertion still means "don't send".
            if returnDecision == .press, !Task.isCancelled {
                // Let the target app finish handling the insertion before Return,
                // then re-check right before posting — the HID event goes to
                // whatever is frontmost at that instant.
                try? await Task.sleep(nanoseconds: 50_000_000)
                if !Task.isCancelled,
                   let target = targetApp?.bundleIdentifier,
                   NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target {
                    TextInsertion.pressReturn()
                    pressReturn = true
                }
            }
            RecordingIndicatorWindowController.shared.hide()
            // Engine names are proper nouns — appended unlocalized so the user
            // can verify which engine actually transcribed.
            let engineName = SpeechEngine.current == .parakeet ? "Parakeet v3" : "Whisper"
            // One toast at the end: a toast shown earlier (during cleanup) would be
            // replaced by this one within milliseconds and never be read.
            var message = copiedInstead
                ? String(localized: "dictation.toast.notesClosedCopied")
                : cleanupNotice ?? String(localized: "dictation.toast.inserted") + " · " + engineName
            if pressReturn {
                message += " · " + String(localized: "dictation.toast.returnPressed")
            } else if returnDecision != .skip {
                // .blocked, or .press withdrawn because the app lost focus.
                message += " · " + String(localized: "dictation.toast.returnWithheld")
            }
            ToastWindowController.shared.show(message: message)
            NSLog("Tippi: dictation inserted \(final.count) chars (raw=\(raw.count)) via \(engineName), return=\(returnDecision) pressed=\(pressReturn)")
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

    /// Fire-and-forget: if dictation post-process is enabled and resolves to
    /// the local MLX provider, start warming its server now instead of
    /// waiting for the first real polish request. Mirrors
    /// `SpeechTranscriber.prewarm()` right above the call site — both let
    /// model loading overlap with the time the user spends speaking.
    /// Resolution mirrors `postProcessIfEnabled`: an explicit per-prompt
    /// override wins, otherwise the global default provider.
    private func warmPostProcessProviderIfNeeded() {
        guard DictationSettings.postProcessEnabled else { return }
        let override = DictationSettings.postProcessProviderOverride
        let provider = override.isEmpty ? LLMRouter.shared.effectivePreferredProviderID() : override
        guard provider == "mlx" else { return }
        Task.detached(priority: .utility) {
            try? await MLXServerManager.shared.start()
        }
    }

    /// Run the raw Whisper transcript through the active LLM provider for
    /// filler-word removal and punctuation, if the user has enabled it.
    /// On any failure (no provider, network error, empty input) returns the
    /// raw transcript unchanged so dictation never breaks because of LLM
    /// trouble.
    private func postProcessIfEnabled(_ raw: String) async -> (text: String, notice: String?) {
        guard DictationSettings.postProcessEnabled else { return (raw, nil) }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (raw, nil) }

        // Short-circuit very short utterances ("ja", "ok", "danke") — the
        // LLM round-trip would dominate perceived latency without adding
        // meaningful cleanup.
        guard trimmed.count >= DictationSettings.postProcessMinChars else {
            NSLog("Tippi: dictation post-process skipped — \(trimmed.count) chars < min \(DictationSettings.postProcessMinChars)")
            return (raw, nil)
        }

        let providerOverride = DictationSettings.postProcessProviderOverride
        let modelOverride    = DictationSettings.postProcessModelOverride

        // Resolve the provider display name before the async call so the
        // indicator pill can show "· ✨ Groq" instead of the generic "· ✨ KI"
        // the moment cleanup starts — no extra round-trip needed.
        let resolvedProviderID = !providerOverride.isEmpty
            ? providerOverride
            : LLMRouter.shared.effectivePreferredProviderID()
        let resolvedProviderName = LLMRouter.providerDisplayName(forID: resolvedProviderID)
        RecordingIndicatorWindowController.shared.show(
            mode: .transcribing,
            recorder: recorder,
            aiEnabled: true,
            providerName: resolvedProviderName
        )

        do {
            // Hard 30s cap: dictation must never hang on the polish step.
            // A local provider cold-starting its server (MLX model load can
            // take minutes) would otherwise leave the user staring at
            // "Transcribing…" — past the cap the raw transcript is inserted.
            let prompt = DictationSettings.effectivePostProcessPrompt
            let result: CompletionResult = try await withThrowingTaskGroup(of: CompletionResult.self) { group in
                group.addTask {
                    if !providerOverride.isEmpty {
                        return try await LLMRouter.shared.complete(
                            systemPrompt: prompt,
                            userText: trimmed,
                            forceProviderID: providerOverride,
                            forceModel: modelOverride,
                            temperature: TaskTemperature.transcriptCleanup
                        )
                    } else {
                        // Cleanup is the one task where deviation IS the
                        // failure — reproduce the input, fix punctuation and
                        // fillers, change nothing else. 0.3 is a
                        // creative-writing default and was wrong here.
                        return try await LLMRouter.shared.complete(
                            systemPrompt: prompt,
                            userText: trimmed,
                            temperature: TaskTemperature.transcriptCleanup
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw CleanupTimeout()
                }
                guard let first = try await group.next() else { throw LLMError.cancelled }
                group.cancelAll()
                return first
            }
            let polished = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !polished.isEmpty else {
                NSLog("Tippi: dictation post-process returned empty — keeping raw")
                return (raw, Self.cleanupFailedNotice(String(localized: "dictation.toast.cleanupEmpty")))
            }
            // Hard rule: dictation cleanup must NEVER respond conversationally.
            // Weak local models (llama3.2:3B etc.) tend to treat short inputs
            // as chat prompts and reply instead of cleaning. If the output
            // looks like a chat response, fall back to the raw transcript
            // and tell the user so the misbehavior is visible, not silent.
            if Self.looksLikeConversationalResponse(input: trimmed, output: polished) {
                NSLog("Tippi: dictation post-process went conversational — falling back to raw (in=\(trimmed.count), out=\(polished.count))")
                return (raw, String(localized: "dictation.toast.cleanupFallback"))
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
            return (polished, nil)
        } catch {
            // The short reason, never the provider's response body — it is
            // foreign text, in the log as much as in the toast.
            let reason = Self.cleanupFailureReason(error)
            NSLog("Tippi: dictation post-process failed — \(reason) — keeping raw")
            return (raw, Self.cleanupFailedNotice(reason))
        }
    }

    nonisolated static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// Thrown by the 30 s cap — distinct from `CancellationError`, which means
    /// the user cancelled and must not be reported as a cleanup failure.
    private struct CleanupTimeout: Error {}

    /// Toast text when cleanup failed and the raw transcript went in instead —
    /// so an unpolished dictation is explained, not a silent mystery.
    private static func cleanupFailedNotice(_ reason: String) -> String {
        String(format: String(localized: "dictation.toast.cleanupFailed"), reason)
    }

    /// Never the raw provider response body in a toast: it is foreign text on
    /// screen (screen shares) in a window that looks like Tippi's own. The full
    /// error stays in the log.
    private static func cleanupFailureReason(_ error: Error) -> String {
        if error is CleanupTimeout {
            return String(localized: "dictation.toast.cleanupTimeout")
        }
        if case LLMError.httpError(let status, _) = error {
            return "HTTP \(status)"
        }
        if case LLMError.providerError = error {
            return String(localized: "dictation.toast.cleanupProviderError")
        }
        return error.localizedDescription
    }

    /// Detects when the cleanup LLM treated the dictation as a prompt and
    /// replied conversationally instead of cleaning the text. Two cheap
    /// heuristics — length blowup and known conversational openers in
    /// DE/EN. False positives are acceptable: the fallback is the raw
    /// transcript (which is what the user actually said), so a wrong
    /// trigger here just means "no cleanup this round", never "wrong text".
    private static func looksLikeConversationalResponse(input: String, output: String) -> Bool {
        // Length blowup: cleaning "Hallo, wie geht's dir?" should not produce
        // 80+ characters. Threshold: 2× input AND > 80 chars (so genuine
        // long-form cleanups aren't flagged).
        if output.count > max(input.count * 2, 80) {
            return true
        }
        let lower = output.lowercased().trimmingCharacters(in: .whitespaces)
        let conversationalStarters = [
            // German
            "ja, ich", "ja ich", "ich verstehe", "ich habe verstanden",
            "natürlich,", "natürlich kann", "klar,", "klar kann",
            "lass mich", "ich werde", "kannst du mir", "könntest du",
            "kein problem", "absolut", "verstanden,", "selbstverständlich",
            // English
            "yes, i", "yes i ", "i understand", "i can help",
            "sure,", "sure i", "of course", "absolutely,",
            "let me", "i'll ", "i will ", "no problem",
            "could you", "would you", "happy to"
        ]
        for starter in conversationalStarters where lower.hasPrefix(starter) {
            return true
        }
        return false
    }
}
