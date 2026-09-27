import AppKit
import os

private let injectorLog = Logger(subsystem: "com.tippi.app", category: "snippet-inject")

/// Deletes the just-typed trigger text and inserts the expansion — the two
/// halves of "type :nl, it turns into the real text". Deletion is synthetic
/// Backspace keystrokes (works in any app, including ones with no
/// Accessibility text-replace support); the actual insert reuses
/// `TextInsertion`'s existing AX/clipboard-fallback path instead of
/// reinventing it.
enum SnippetTextInjector {
    /// Deletes the trigger right away — before the replacement is resolved.
    /// Resolving a shell variable can take up to its 5 s timeout; keys typed
    /// meanwhile reached the app, and backspaces sent afterwards deleted those
    /// instead of the trigger (audit 2026-09-27).
    @MainActor
    static func deleteTrigger(length: Int) {
        sendBackspaces(count: length)
    }

    /// Inserts the resolved replacement where the trigger was.
    @MainActor
    static func insert(_ replacement: String) async {
        // Espanso's `$|$` marks where the caret belongs. Strip it before typing —
        // otherwise it lands in the user's text verbatim — and remember how far
        // back to move afterwards.
        let (text, caretOffset) = SnippetCursorHint.split(replacement)
        // Short settle delay before the paste roundtrip — mirrors the 40ms
        // pre-paste delay `TextInsertion.paste` already uses; without it,
        // a fast backspace-then-paste sequence can race ahead of the target
        // app's own event processing.
        try? await Task.sleep(nanoseconds: 20_000_000)
        await TextInsertion.insertViaClipboard(text, into: NSWorkspace.shared.frontmostApplication)

        guard caretOffset > 0 else { return }
        // Same reasoning as the pre-paste delay: the arrow keys must not overtake
        // the paste the target app is still processing, or they move the caret
        // from the wrong starting point.
        try? await Task.sleep(nanoseconds: 30_000_000)
        moveCaretLeft(count: caretOffset)
    }

    /// Moves the insertion point back by `count` characters using synthetic
    /// arrow keys — the same approach as the backspaces above, and for the same
    /// reason: it works in every app, including ones without Accessibility
    /// text APIs.
    private static func moveCaretLeft(count: Int) {
        guard count > 0 else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let leftArrow: CGKeyCode = 123 // kVK_LeftArrow

        for _ in 0..<count {
            // Flags cleared like the backspaces below: a still-held ⌥ would make
            // this ⌥← (jump a word) instead of one character.
            let down = CGEvent(keyboardEventSource: src, virtualKey: leftArrow, keyDown: true)
            down?.flags = []
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: leftArrow, keyDown: false)
            up?.flags = []
            up?.post(tap: .cghidEventTap)
        }
        injectorLog.notice("moved caret back \(count) character(s) for cursor hint")
    }

    private static func sendBackspaces(count: Int) {
        guard count > 0 else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let deleteKey: CGKeyCode = 51 // kVK_Delete (Backspace)

        for _ in 0..<count {
            // Explicitly no modifiers: since ⌥ characters count, a trigger can
            // complete on a keystroke with ⌥ still held (`:-|` on a German
            // layout) — a `.hidSystemState` event would inherit it and turn ⌫
            // into ⌥⌫, deleting whole words of the user's text (review 2026-09-27).
            let down = CGEvent(keyboardEventSource: src, virtualKey: deleteKey, keyDown: true)
            down?.flags = []
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: deleteKey, keyDown: false)
            up?.flags = []
            up?.post(tap: .cghidEventTap)
        }
        injectorLog.notice("sent \(count) synthetic backspace(s) for trigger deletion")
    }
}
