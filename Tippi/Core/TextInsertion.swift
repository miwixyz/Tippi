import AppKit
import ApplicationServices

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
        if replaceSelectionViaAccessibility(with: text) {
            return
        }

        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()

        pb.clearContents()
        pb.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms — settle clipboard
        simulatePaste()
        try? await Task.sleep(nanoseconds: 750_000_000) // let slower target apps consume the pasteboard

        snapshot.restore()
    }

    private static func replaceSelectionViaAccessibility(with text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusStatus == .success, let focusedRaw = focusedRef else { return false }

        let focused = focusedRaw as! AXUIElement
        let status = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return status == .success
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
