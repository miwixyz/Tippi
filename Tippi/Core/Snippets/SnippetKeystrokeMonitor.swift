import AppKit
import ApplicationServices
import os

private let monitorLog = Logger(subsystem: "com.tippi.app", category: "snippet-monitor")

/// System-wide "type a trigger, it expands itself" engine — the Espanso-style
/// mechanism. Uses `NSEvent.addGlobalMonitorForEvents` (same approach as
/// `GlobalKeyMonitor`): Accessibility permission only, no Input Monitoring
/// prompt, because this never needs to *suppress* the original keystrokes —
/// it only reacts afterwards with corrective backspaces.
@MainActor
final class SnippetKeystrokeMonitor: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastError: String?

    private var matcher = SnippetMatcher()
    private let store: SnippetStore

    /// Emoji suggestions for the `:prefix` currently being typed, newest first.
    /// Held here (not only in the panel) because the Space shortcut needs to
    /// know the top entry, and the panel is a pure renderer.
    private var currentSuggestions: [Emoji] = []

    /// Called with the ranked suggestions whenever the typed `:prefix`
    /// changes, and with an empty array when the list should disappear. The
    /// UI layer owns the panel — Core stays free of AppKit windows.
    var onSuggestionsChanged: (([Emoji]) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?

    /// Set while sending our own corrective backspace+paste, so those
    /// synthetic events don't feed back into the matcher and corrupt the
    /// buffer or re-trigger on our own output.
    private var isInjecting = false

    /// Keys that reset the buffer instead of being appended to it — a
    /// Return/Tab/Escape means "no longer mid-word", an arrow key means the
    /// cursor moved somewhere the buffer no longer describes. Espanso resets
    /// on the same class of keys.
    private static let resetKeyCodes: Set<UInt16> = [36, 48, 53, 123, 124, 125, 126] // Return, Tab, Escape, ←→↓↑
    private static let deleteKeyCode: UInt16 = 51

    init(store: SnippetStore) {
        self.store = store
    }

    func start() {
        guard !isActive else { return }
        lastError = nil

        guard AXIsProcessTrusted() else {
            lastError = "Grant Accessibility permission so snippet expansion can watch typed text."
            monitorLog.notice("SnippetKeystrokeMonitor — not trusted (Accessibility permission missing)")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }

        // A different app (or window) means the buffer no longer reflects
        // what's actually behind the cursor — stale buffer content must
        // never survive a context switch.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.matcher.reset() }
        }

        guard globalMonitor != nil else {
            lastError = "Couldn't register snippet keystroke monitor."
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            return
        }

        isActive = true
        monitorLog.notice("SnippetKeystrokeMonitor active")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let o = appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        globalMonitor = nil
        localMonitor = nil
        appSwitchObserver = nil
        isActive = false
        matcher.reset()
    }

    private func handle(_ event: NSEvent) {
        guard !isInjecting else { return }
        // Never expand while Tippi itself is the frontmost app — typing a
        // trigger string into the "new snippet" editor in Settings must not
        // expand itself.
        if NSApp.isActive { return }

        if event.keyCode == Self.deleteKeyCode {
            matcher.deleteLastCharacter()
            refreshSuggestions()
            return
        }
        if Self.resetKeyCodes.contains(event.keyCode) {
            // Return/Tab/Escape/arrows all mean "no longer mid-word", so the
            // suggestion list is stale — and Escape in particular is how a user
            // dismisses it.
            matcher.reset()
            clearSuggestions()
            return
        }
        // charactersIgnoringModifiers still reflects Shift (":" from
        // Shift+;) but not Option/Command, so ⌥/⌘ combos never pollute the
        // buffer with dead-key or shortcut side effects.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            return
        }
        for char in chars {
            matcher.appendCharacter(char)
        }

        // Snippets are checked first on purpose: a user-defined snippet whose
        // trigger happens to look like an emoji name (":ok:") must win over
        // the built-in emoji of the same name. Explicit configuration beats a
        // shipped default.
        if let trigger = matcher.matchedTrigger(among: store.activeTriggers()),
           let action = store.action(forTrigger: trigger) {
            expand(triggerLength: trigger.count) { [store] in await store.resolve(action) }
            return
        }

        // `:rakete:` → 🚀. Only fires for a well-formed name that resolves to
        // a real emoji; anything else leaves the typed text untouched.
        if EmojiSettings.isInlineEnabled,
           let candidate = EmojiInlineMatcher.candidate(in: matcher.buffer),
           let emoji = EmojiDatabase.shared.emoji(forAlias: candidate.alias) {
            EmojiSettings.rememberUse(of: emoji.character)
            expand(triggerLength: candidate.triggerLength) { emoji.character }
            return
        }

        // `:-)` → 🙂. Checked last of the three expansions: an emoticon has no
        // closing delimiter, so it is the loosest pattern and must not
        // pre-empt an explicit snippet trigger or a `:name:` shortcode.
        if EmojiSettings.isEmoticonEnabled,
           let emoticon = EmoticonMatcher.match(in: matcher.buffer) {
            EmojiSettings.rememberUse(of: emoticon.emoji)
            clearSuggestions()
            expand(triggerLength: emoticon.triggerLength) { emoticon.emoji }
            return
        }

        // Space accepts the highlighted suggestion: `:lach` + ␣ → "😂 ".
        //
        // Space rather than Tab or Return, because this monitor cannot swallow
        // keystrokes — the character always reaches the target app first and is
        // retracted afterwards by backspaces. A space is the one key that
        // reliably inserts exactly one character everywhere; Tab moves focus to
        // the next field in Mail and Slack (the backspaces would then hit the
        // wrong field), and Return sends the message.
        if !currentSuggestions.isEmpty,
           matcher.buffer.hasSuffix(" "),
           let top = currentSuggestions.first,
           let prefix = EmojiInlineMatcher.openPrefix(in: String(matcher.buffer.dropLast())) {
            EmojiSettings.rememberUse(of: top.character)
            clearSuggestions()
            // ":" + prefix + the space just typed. The replacement re-adds the
            // space so the user can keep typing without a missing separator.
            expand(triggerLength: prefix.count + 2) { top.character + " " }
            return
        }

        refreshSuggestions()
    }

    /// Recomputes the suggestion list for the `:prefix` at the end of the
    /// buffer. Cheap when there is no open prefix (the common case): the
    /// database is only searched once a colon-led word is actually in
    /// progress, so ordinary typing never pays for it.
    private func refreshSuggestions() {
        guard EmojiSettings.isInlineEnabled, EmojiSettings.isSuggestionsEnabled else {
            clearSuggestions()
            return
        }
        guard let prefix = EmojiInlineMatcher.openPrefix(in: matcher.buffer) else {
            clearSuggestions()
            return
        }
        let matches = EmojiDatabase.shared.search(prefix, limit: EmojiSuggestionPanel.maxSuggestions)
        guard !matches.isEmpty else {
            clearSuggestions()
            return
        }
        currentSuggestions = matches
        onSuggestionsChanged?(matches)
    }

    private func clearSuggestions() {
        guard !currentSuggestions.isEmpty else { return }
        currentSuggestions = []
        onSuggestionsChanged?([])
    }

    /// Inserts a suggestion the user clicked, replacing the `:prefix` they had
    /// typed so far. Called from the panel via the UI layer.
    func acceptSuggestion(_ emoji: Emoji) {
        guard let prefix = EmojiInlineMatcher.openPrefix(in: matcher.buffer) else {
            clearSuggestions()
            return
        }
        EmojiSettings.rememberUse(of: emoji.character)
        clearSuggestions()
        expand(triggerLength: prefix.count + 1) { emoji.character }
    }

    /// Shared tail of both expansion paths: clear the buffer, block re-entry,
    /// resolve the replacement, and inject it.
    ///
    /// `defer`, not a bare trailing assignment: the real bug this guards
    /// against (2026-09-09 pre-release audit) was a shell-var resolution that
    /// could hang indefinitely (now fixed with its own timeout in
    /// `SnippetVariableResolver`, but this is the second line of defense) —
    /// without `defer`, any future path through resolve/replace that throws or
    /// returns early would leave `isInjecting` stuck `true` forever, silently
    /// and permanently disabling expansion until the app restarts.
    private func expand(triggerLength: Int, resolve: @escaping () async -> String) {
        matcher.reset()
        isInjecting = true
        Task { @MainActor in
            defer { isInjecting = false }
            let text = await resolve()
            await SnippetTextInjector.replace(triggerLength: triggerLength, with: text)
        }
    }
}
