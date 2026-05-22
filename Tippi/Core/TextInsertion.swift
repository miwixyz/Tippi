import AppKit
import ApplicationServices
import os

private let insertLog = Logger(subsystem: "com.tippi.app", category: "insert")

@MainActor
enum TextInsertion {
    static func replace(with text: String, in app: NSRunningApplication?) async {
        if let app, replaceSelectionViaAccessibility(with: text, in: app) {
            insertLog.notice("AX replace ok (\(text.count) chars)")
            return
        }
        if replaceSelectionViaAccessibility(with: text) {
            insertLog.notice("AX replace (focused) ok")
            return
        }

        insertLog.notice("AX replace failed → clipboard+paste fallback")
        app?.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 150_000_000)
        await paste(text: text)
        insertLog.notice("clipboard paste done")
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

    /// Re-selects `range` on `element` then replaces it with `text`, all via Accessibility.
    /// Works cross-app without the source app being frontmost. Used by local quick actions
    /// where the popup collapsed the live selection — we restore it from the captured range.
    static func replaceViaElement(_ element: AXUIElement, range: CFRange, with text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let valueBefore = axStringValue(element)

        var mutableRange = range
        if let axRange = AXValueCreate(.cfRange, &mutableRange) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        let valueAfter = axStringValue(element)

        // Electron/Chromium apps return .success for an AX text write but silently
        // ignore it. Detect that: if the element exposed its value and it did not
        // change, the write was a no-op → report failure so the caller falls back.
        let noOp = valueBefore != nil && valueAfter != nil && valueBefore == valueAfter
        let effective = result == .success && !noOp
        insertLog.notice("replaceViaElement set=\(result.rawValue, privacy: .public) noOp=\(noOp, privacy: .public) effective=\(effective, privacy: .public)")
        return effective
    }

    private static func axStringValue(_ element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
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
        let before = axStringValue(element)
        let ok = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
        guard ok else { return false }

        // Treat a value-unchanged write as a failure so the caller falls back to ⌘V
        // (Electron/Chromium report success but ignore AX text writes).
        let after = axStringValue(element)
        if let before, let after, before == after {
            insertLog.notice("setSelectedText no-op (value unchanged)")
            return false
        }
        return true
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

        // Post to a single tap only. Posting to both cghidEventTap and
        // cgAnnotatedSessionEventTap makes Electron/Chromium apps process the ⌘V
        // twice, pasting the text two times.
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
