import AppKit
import ApplicationServices

@MainActor
enum TextInsertion {
    static func replace(with text: String, in app: NSRunningApplication?) async {
        if let app, replaceSelectionViaAccessibility(with: text, in: app) {
            NSLog("Tippi: TextInsertion AX replace ok")
            return
        }
        if replaceSelectionViaAccessibility(with: text) {
            NSLog("Tippi: TextInsertion AX replace (focused) ok")
            return
        }

        app?.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 150_000_000)
        await paste(text: text)
    }

    static func replace(with text: String) async {
        await replace(with: text, in: nil)
    }

    static func replace(with attributedText: NSAttributedString, fallbackPlainText: String, in app: NSRunningApplication?) async {
        if let app, replaceSelectionViaAccessibility(with: fallbackPlainText, in: app) {
            return
        }
        if replaceSelectionViaAccessibility(with: fallbackPlainText) {
            return
        }

        app?.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 150_000_000)
        await paste(attributedText: attributedText, fallbackPlainText: fallbackPlainText)
    }

    static func replace(with attributedText: NSAttributedString, fallbackPlainText: String) async {
        await replace(with: attributedText, fallbackPlainText: fallbackPlainText, in: nil)
    }

    static func append(_ text: String) async {
        await paste(text: text)
    }

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

        try? await Task.sleep(nanoseconds: 40_000_000)
        simulatePaste()
        try? await Task.sleep(nanoseconds: 400_000_000)

        snapshot.restore()
    }

    private static func paste(attributedText: NSAttributedString, fallbackPlainText: String) async {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()

        pb.clearContents()
        if let rtf = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(fallbackPlainText, forType: .string)

        try? await Task.sleep(nanoseconds: 40_000_000)
        simulatePaste()
        try? await Task.sleep(nanoseconds: 400_000_000)

        snapshot.restore()
    }

    private static func replaceSelectionViaAccessibility(with text: String, in app: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        if let focused = focusedElement(in: appElement),
           setSelectedText(text, on: focused) {
            return true
        }

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let element = findElementWithSelection(in: window, depth: 0),
                   setSelectedText(text, on: element) {
                    return true
                }
            }
        }

        return false
    }

    private static func replaceSelectionViaAccessibility(with text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRaw = focusedRef else {
            return false
        }

        return setSelectedText(text, on: focusedRaw as! AXUIElement)
    }

    private static func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private static func findElementWithSelection(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 14 else { return nil }

        var rangeRef: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success

        var selectedRef: CFTypeRef?
        let hasSelected = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success

        if hasSelected || hasRange {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let match = findElementWithSelection(in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private static func focusedElement(in appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRaw = focusedRef else {
            return nil
        }
        return (focusedRaw as! AXUIElement)
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // V

        for tap in [CGEventTapLocation.cghidEventTap, .cgAnnotatedSessionEventTap] {
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: tap)

            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: tap)
        }
    }
}
