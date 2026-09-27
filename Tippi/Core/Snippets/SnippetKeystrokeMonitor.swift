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

    /// When the watcher last *received* a key event — set before any filtering,
    /// so it answers one question and only one: are keystrokes arriving at all?
    ///
    /// `isActive` cannot answer it: `addGlobalMonitorForEvents` returns a
    /// non-nil token even without permission and then never delivers anything,
    /// so the watcher reported "running" while nothing expanded (2026-09-14).
    @Published private(set) var lastKeystrokeAt: Date?

    /// When an event last survived filtering and reached the matcher. If
    /// `lastKeystrokeAt` advances but this does not, events arrive and are
    /// being discarded — e.g. because Tippi itself is the frontmost app.
    @Published private(set) var lastProcessedAt: Date?

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
    /// buffer or re-trigger on our own output. Readable so the autocomplete
    /// can stay quiet while an expansion is being typed.
    private(set) var isInjecting = false

    /// Keys that reset the buffer instead of being appended to it — a
    /// Return/Tab/Escape means "no longer mid-word", an arrow key means the
    /// cursor moved somewhere the buffer no longer describes. Espanso resets
    /// on the same class of keys.
    private static let resetKeyCodes: Set<UInt16> = [
        36, 48, 53, 123, 124, 125, 126,   // Return, Tab, Escape, ←→↓↑
        115, 116, 117, 119, 121,          // Home, PgUp, Forward Delete, End, PgDn
    ]
    private static let deleteKeyCode: UInt16 = 51

    init(store: SnippetStore) {
        self.store = store
    }

    func start() {
        guard !isActive else { return }
        lastError = nil

        guard AXIsProcessTrusted() else {
            lastError = String(localized: "error.accessibility.snippets")
            monitorLog.notice("SnippetKeystrokeMonitor — not trusted (Accessibility permission missing)")
            return
        }

        // Mouse clicks too: a click moves the caret somewhere the buffer no
        // longer describes. Without this, `:da` + click + `te` matched `:date`
        // and the backspaces deleted unrelated text at the new spot (audit
        // 2026-09-27). Still one watcher — the same monitors, a wider mask.
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        monitorLog.notice(
            "start(): trusted=\(AXIsProcessTrusted()) globalMonitor=\(self.globalMonitor != nil) localMonitor=\(self.localMonitor != nil) snippetsEnabled=\(self.store.isEnabled)")

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
            lastError = String(localized: "error.monitor.snippets")
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

    /// Identifiers of Tippi's own windows where snippet expansion is wanted.
    /// Currently just Notes; Settings and Welcome stay suppressed because a
    /// trigger typed there is being *defined*, not used.
    static let expansionAllowedWindowIdentifiers: Set<String> = ["TippiNotesWindow"]

    /// Pure decision so it is testable without building windows: given the
    /// identifier of the key window while Tippi is frontmost, should the
    /// keystroke be dropped?
    ///
    /// `nil` (an unidentified window, or no key window at all) discards — the
    /// conservative direction. A window has to say what it is to get expansion.
    static func shouldDiscardWhileFrontmost(keyWindowIdentifier: String?) -> Bool {
        guard let id = keyWindowIdentifier else { return true }
        return !expansionAllowedWindowIdentifiers.contains(id)
    }

    private func handle(_ event: NSEvent) {
        if event.type != .keyDown {
            // A click in Tippi's own suggestion list is a pick, not a caret
            // move: resetting here closed the list on mouse-down, before the
            // pick fires on mouse-up (review 2026-09-27).
            if event.window is NonKeyPanel { return }
            matcher.reset()
            clearSuggestions()
            return
        }
        // Recorded before every guard below: this is the only honest answer to
        // "do keystrokes reach the watcher at all?"
        lastKeystrokeAt = Date()
        // `.debug`, never `.notice`: this fires on every single keystroke the
        // user types in any app. At `.notice` it is written to the persistent
        // system log, so `log show` replays hours of key codes for anything
        // typed while Tippi runs — passwords included. `.debug` is only
        // materialised while someone actively streams the log, which is
        // exactly when it is wanted. `lastKeystrokeAt` above carries the
        // diagnostic value (are keystrokes arriving at all?) without recording
        // what was typed.
        monitorLog.debug(
            "keystroke received keyCode=\(event.keyCode) injecting=\(self.isInjecting) appActive=\(NSApp.isActive)")

        guard !isInjecting else {
            monitorLog.debug("  → discarded: isInjecting")
            return
        }
        // Suppression is per *window*, not per app.
        //
        // The reason this guard exists is the snippet editor in Settings:
        // typing a trigger there to *define* it must not expand it. The old
        // condition was a bare `NSApp.isActive`, which is app-wide — so it
        // also silenced the Notes window, an ordinary editing surface added
        // later where a user reasonably expects `:trigger` to work. Reported
        // 2026-09-20 ("in Tippi Notizen funktioniert Snippets nicht, :
        // reagiert nicht"); the keystroke arrived and was discarded one line
        // below, which is why nothing in the UI hinted at a cause.
        //
        // Allow-list, not deny-list: only windows that explicitly declare
        // themselves a text surface opt in. A future Tippi window is
        // suppressed by default rather than silently starting to expand.
        if NSApp.isActive,
           Self.shouldDiscardWhileFrontmost(keyWindowIdentifier: NSApp.keyWindow?.identifier?.rawValue) {
            monitorLog.debug("  → discarded: Tippi frontmost and key window is not a snippet surface")
            return
        }

        lastProcessedAt = Date()

        if event.keyCode == Self.deleteKeyCode {
            // ⌥⌫ / ⌘⌫ delete a word or a line, not one character.
            if event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
                matcher.deleteLastCharacter()
            } else {
                matcher.reset()
            }
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
        // ⌘/⌃ shortcuts (⌘V, ⌘Z, ⌘A …) change the text in ways the buffer
        // cannot follow — start over.
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else {
            matcher.reset()
            clearSuggestions()
            return
        }
        // Without ⌥: charactersIgnoringModifiers (still reflects Shift).
        // With ⌥: the character actually typed — on a German layout `@ | \ [ ]
        // { }` all need ⌥, and dropping them meant `:-|` or `\o/` could never
        // match (audit 2026-09-27). Dead keys (⌥N for `~`, `^`) yield "" and
        // add nothing, so triggers containing those still cannot match.
        let typed = event.modifierFlags.contains(.option) ? event.characters : event.charactersIgnoringModifiers
        guard let chars = typed, !chars.isEmpty else { return }
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
            expand(triggerLength: emoticon.triggerLength) { emoticon.replacement }
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
        // Every expansion path ends here, so closing the suggestion list once in
        // this one place cannot be forgotten in a new branch. Two branches did
        // forget it (snippet trigger and `:name:` shortcode), which left the
        // emoji list hanging over text that had already been replaced.
        clearSuggestions()
        isInjecting = true
        SnippetTextInjector.deleteTrigger(length: triggerLength)
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { @MainActor in
            defer { isInjecting = false }
            let text = await resolve()
            // Resolving a shell var can take seconds. If the user switched
            // apps meanwhile, its output must not land in the new one
            // (Rafter 2026-09-27) — drop it instead.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
                monitorLog.notice("snippet expansion dropped: frontmost app changed while resolving")
                return
            }
            await SnippetTextInjector.insert(text)
        }
    }
}
