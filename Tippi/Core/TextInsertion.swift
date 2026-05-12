import AppKit

@MainActor
enum TextInsertion {
    /// Replace the current selection in the focused app with `text`.
    static func replace(with text: String) async {
        await paste(text: text)
    }

    /// Append `text` immediately after the current selection / cursor.
    /// Phase 2: equivalent to `replace` (pastes at cursor).
    /// Phase 3 will move the cursor to selection-end via AX before pasting.
    static func append(_ text: String) async {
        await paste(text: text)
    }

    /// Copy `text` to the clipboard without pasting.
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Paste roundtrip

    private static func paste(text: String) async {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()

        pb.clearContents()
        pb.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms — settle clipboard
        simulatePaste()
        try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms — let target app paste

        snapshot.restore()
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // V

        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
