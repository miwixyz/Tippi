import AppKit
import ApplicationServices

struct CapturedText {
    let text: String
    let sourceApp: NSRunningApplication?
    let usedClipboardFallback: Bool
}

@MainActor
enum TextCapture {
    /// Read the currently selected text from the focused application.
    /// Tries the Accessibility API first; falls back to a transparent
    /// pasteboard ⌘C round-trip if AX cannot read the selection.
    static func captureSelectedText(sourceApp: NSRunningApplication?) async -> CapturedText? {
        if let text = readViaAccessibility(), !text.isEmpty {
            return CapturedText(text: text, sourceApp: sourceApp, usedClipboardFallback: false)
        }

        if let text = await readViaPasteboard(), !text.isEmpty {
            return CapturedText(text: text, sourceApp: sourceApp, usedClipboardFallback: true)
        }

        return nil
    }

    // MARK: - Accessibility path

    private static func readViaAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusStatus == .success, let focusedRaw = focusedRef else { return nil }
        let focused = focusedRaw as! AXUIElement

        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard selectedStatus == .success else { return nil }
        return selectedRef as? String
    }

    // MARK: - Pasteboard fallback

    private static func readViaPasteboard() async -> String? {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()
        let changeCountBefore = pb.changeCount

        simulateCopy()

        let deadline = Date().addingTimeInterval(0.3)
        while pb.changeCount == changeCountBefore && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }

        let captured = pb.string(forType: .string)
        snapshot.restore()
        return captured
    }

    private static func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cKey: CGKeyCode = 8 // C

        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
