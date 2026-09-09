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
            return
        }
        if Self.resetKeyCodes.contains(event.keyCode) {
            matcher.reset()
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

        guard let trigger = matcher.matchedTrigger(among: store.activeTriggers()),
              let action = store.action(forTrigger: trigger) else {
            return
        }

        matcher.reset()
        isInjecting = true
        Task { @MainActor in
            // `defer`, not a bare trailing assignment: the real bug this
            // guards against (2026-09-09 pre-release audit) was a shell-var
            // resolution that could hang indefinitely (now fixed with its
            // own timeout in SnippetVariableResolver, but this is the
            // second line of defense) — without `defer`, any future path
            // through `resolve`/`replace` that throws or returns early
            // would leave `isInjecting` stuck `true` forever, silently and
            // permanently disabling snippet expansion until app restart.
            defer { isInjecting = false }
            let text = await store.resolve(action)
            await SnippetTextInjector.replace(triggerLength: trigger.count, with: text)
        }
    }
}
