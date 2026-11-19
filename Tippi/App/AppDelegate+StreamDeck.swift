import AppKit
import OSLog

private let deckLog = Logger(subsystem: "com.tippi.app", category: "streamdeck")

/// Stream Deck (docs/SECURE-DESIGN-stream-deck.md): checked commands from the plugin run the same paths as Tippi's
/// hot keys and menu items, on the app in front. Results never go back to the plugin – only state (D4).
extension AppDelegate {

    func startStreamDeck() {
        streamDeck.onCommand = { [weak self] c in self?.handleDeckCommand(c) }
        streamDeck.onDisconnect = { [weak self] in self?.deckDisconnected() }
        streamDeck.status = { [weak self] withPrompts in self?.deckStatus(withPrompts: withPrompts) ?? DeckWire.Status() }
        streamDeck.apply()
    }

    private func handleDeckCommand(_ c: DeckWire.Command) {
        switch c {
        case .hello, .watch:
            break
        case .dictation(let step, let mode):
            deckLog.notice("Stream Deck: dictation \(step.rawValue, privacy: .public)")
            Task { @MainActor in await self.deckDictation(step, mode: mode) }
        case .run(let action):
            deckLog.notice("Stream Deck: run \(action.rawValue, privacy: .public)")
            Task { @MainActor in await self.deckRun(action) }
        case .prompt(let id):
            deckLog.notice("Stream Deck: prompt")
            Task { @MainActor in await self.deckPrompt(id) }
        }
    }

    // MARK: Dictation

    private var dictationReady: Bool { DictationSettings.isEnabled && SpeechEngine.isCurrentEngineReady }

    private func deckDictation(_ step: DeckWire.DictationStep, mode: DeckWire.ModeSlot) async {
        let target = resolvedSourceAppForCapture()
        switch step {
        case .toggle:
            guard dictationReady else { return ToastWindowController.shared.show(message: String(localized: "streamdeck.dictationOff")) }
            await dictationController.toggle(targetApp: target, notesTextView: Self.focusedNotesTextView(),
                                             source: Self.dictationSource(for: mode))
        case .holdStart:
            guard dictationReady, dictationController.state == .idle else {
                if !dictationReady { ToastWindowController.shared.show(message: String(localized: "streamdeck.dictationOff")) }
                return
            }
            deckHoldActive = true
            await dictationController.beginHoldRecording(source: Self.dictationSource(for: mode))
        case .holdEnd:
            guard deckHoldActive else { return }
            deckHoldActive = false
            dictationController.endHoldRecording(targetApp: target, notesTextView: Self.focusedNotesTextView())
        }
    }

    /// D5: a held dictation never outlives the plugin – a lost connection ends it like releasing the key.
    private func deckDisconnected() {
        guard deckHoldActive else { return }
        deckHoldActive = false
        deckLog.notice("Stream Deck: plugin gone while holding – dictation ended")
        dictationController.endHoldRecording(targetApp: resolvedSourceAppForCapture(),
                                             notesTextView: Self.focusedNotesTextView())
    }

    /// Slot → Tippi's own mode assignment, like the extra modifier on the dictation key. Empty slot → standard.
    static func dictationSource(for slot: DeckWire.ModeSlot) -> DictationSource {
        guard DictationModes.isEnabled, let s = DictationModeSlot(rawValue: slot.rawValue),
              let mode = DictationModes.resolve(DictationModes.assignment(for: s), slot: s, lookup: DemoPrompt.resolve(id:))
        else { return .standard }
        return .mode(mode)
    }

    // MARK: Actions

    private func deckRun(_ action: DeckWire.Action) async {
        switch action {
        case .mailDictation:
            guard dictationReady else { return ToastWindowController.shared.show(message: String(localized: "streamdeck.dictationOff")) }
            await dictationController.toggle(targetApp: resolvedSourceAppForCapture(),
                                             notesTextView: Self.focusedNotesTextView(), source: .mail)
        case .voiceNote:
            guard dictationReady else { return ToastWindowController.shared.show(message: String(localized: "streamdeck.dictationOff")) }
            await handleVoiceNoteHotkey()
        case .reply:
            guard dictationReady else { return ToastWindowController.shared.show(message: String(localized: "streamdeck.dictationOff")) }
            guard ReplySettings.isEnabled else {
                return ToastWindowController.shared.show(message: String(localized: "streamdeck.replyOff"))
            }
            await dictationController.toggle(targetApp: resolvedSourceAppForCapture(), source: .reply)
        case .popup:
            guard deckAIAllowed() else { return }
            await handleTriggered(from: .manual)
        case .translate:
            await toggleTranslatePanel()
        case .emoji:
            emojiPickerPanel.toggle()
        case .notes:
            showNotesWindow()
        case .quickNotes:
            openQuickNotesFromURL()
        case .screenText:
            beginScreenOCR()
        case .password:
            generatePasswordFromMenu()
        case .pause:
            togglePause()
        case .autocomplete:
            toggleAutocomplete()
        case .language:
            let langs = Self.dictationLanguages
            let i = langs.firstIndex { $0.code == WhisperConfig.language } ?? -1
            let next = langs[(i + 1) % langs.count]
            WhisperConfig.language = next.code
            rebuildDictationLanguageMenu()
            ToastWindowController.shared.show(message: next.label)
        }
    }

    /// D5: at most one AI command every 1.5 s (cost guard), plus Tippi's own "already working" lock.
    private func deckAIAllowed() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(deckLastAI) >= 1.5 else {
            deckLog.notice("Stream Deck: AI command dropped (too soon)")
            return false
        }
        deckLastAI = now
        return true
    }

    /// Runs one prompt on the selection, without the popup. The prompt text always comes from Tippi; the result goes
    /// to the preview for confirmation, never to the plugin.
    private func deckPrompt(_ id: String) async {
        guard let prompt = DemoPrompt.resolve(id: id) else {
            return ToastWindowController.shared.show(message: String(localized: "streamdeck.promptMissing"))
        }
        guard deckAIAllowed(), !isHandlingTrigger, !popupController.isOpen, !previewWindowController.isOpen else { return }
        isHandlingTrigger = true
        defer { isHandlingTrigger = false }
        let (_, captured) = await captureForTrigger()
        guard let captured else {
            return ToastWindowController.shared.show(message: String(localized: "local.action.noSelection"))
        }
        showPreview(prompt: prompt, captured: captured)
    }

    // MARK: State

    private func deckStatus(withPrompts: Bool) -> DeckWire.Status {
        var s = DeckWire.Status()
        switch dictationController.state {
        case .idle: s.dictation = .idle
        case .recording: s.dictation = .recording
        case .transcribing: s.dictation = .transcribing
        }
        if s.dictation == .recording {
            s.level = Int((min(1, max(0, audioRecorder.level)) * Float(DeckWire.maxLevel)).rounded())
        }
        if s.dictation != .idle {
            s.source = switch dictationController.source {
            case .standard: "standard"
            case .mail: "mail"
            case .mode: "mode"
            case .inbox: "inbox"
            case .reply: "reply"
            }
        }
        s.ready = dictationReady
        s.paused = TippiPause.isActive()
        s.autocomplete = AutocompleteSettings.isEnabled
        s.language = WhisperConfig.language
        if withPrompts {
            s.prompts = DemoPrompt.all.prefix(DeckWire.maxPrompts).map { DeckWire.Item(id: $0.id, title: $0.title) }
        }
        // Modes resolve against the prompt list – only as often as the prompts themselves.
        if withPrompts, DictationModes.isEnabled {
            s.modes = DictationModeSlot.allCases.compactMap { slot in
                DictationModes.resolve(DictationModes.assignment(for: slot), slot: slot, lookup: DemoPrompt.resolve(id:))
                    .map { DeckWire.Item(id: slot.rawValue, title: $0.title) }
            }
        }
        return s
    }
}
