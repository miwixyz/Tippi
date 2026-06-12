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

    /// Bypasses AX entirely and inserts `text` via clipboard + synthetic ⌘V.
    /// Use when AX has already been attempted and confirmed to be a no-op
    /// (e.g. `.ignored` outcome from `replaceViaElement`).
    static func insertViaClipboard(_ text: String, into app: NSRunningApplication?) async {
        app?.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 150_000_000)
        await paste(text: text)
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Paste roundtrip

    /// Marker type from nspasteboard.org: clipboard managers (Maccy, Paste,
    /// Alfred, …) skip pasteboard entries carrying it. Our paste roundtrip is
    /// transient by nature — the AI result must not end up in their archives.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private static func paste(text: String) async {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()

        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setString("", forType: concealedType)

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
        pb.setString("", forType: concealedType)

        try? await Task.sleep(nanoseconds: 40_000_000)
        simulatePaste()
        try? await Task.sleep(nanoseconds: 400_000_000)

        snapshot.restore()
    }

    /// Re-selects `range` on `element` then replaces it with `text`, all via Accessibility.
    /// Works cross-app without the source app being frontmost. Used by local quick actions
    /// where the popup collapsed the live selection — we restore it from the captured range.
    enum AXReplaceOutcome {
        /// AX write took effect — text replaced.
        case replaced
        /// AX reported success but the value did not change (Electron/Chromium
        /// ignore AX text writes). The selection is also gone, so a ⌘V would append.
        case ignored
        /// AX could not be used (not trusted, or write returned an error).
        case unavailable
    }

    static func replaceViaElement(
        _ element: AXUIElement,
        range: CFRange,
        with text: String,
        expecting expectedText: String? = nil
    ) -> AXReplaceOutcome {
        guard AXIsProcessTrusted() else { return .unavailable }

        // The range was captured at trigger time; the LLM round-trip takes
        // seconds. If the user edited the document meanwhile, the range points
        // at different text. Diagnose-only for now: AXStringForRange proved
        // unreliable as a hard gate in the 2026-06-10 field test (false
        // mismatches blocked legitimate replaces), so we log instead of
        // refusing until the mismatch sources are understood.
        if let expectedText,
           let current = axString(for: range, in: element),
           current.trimmingCharacters(in: .whitespacesAndNewlines)
               != expectedText.trimmingCharacters(in: .whitespacesAndNewlines) {
            insertLog.notice("replaceViaElement: range content differs from capture (len \(current.count) vs \(expectedText.count)) — proceeding anyway")
        }

        let valueBefore = axStringValue(element)

        var mutableRange = range
        if let axRange = AXValueCreate(.cfRange, &mutableRange) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }

        // Capture selectedText *after* the range re-selection, before the write.
        // Used as a secondary no-op detector for apps that don't expose kAXValueAttribute
        // (Electron/Chromium) but do expose kAXSelectedTextAttribute.
        var selectedBeforeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedBeforeRef)
        let selectedBefore = selectedBeforeRef as? String

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard result == .success else {
            insertLog.notice("replaceViaElement → unavailable (set=\(result.rawValue, privacy: .public))")
            return .unavailable
        }

        // If the element exposed its value and it did not change, the write was a
        // no-op (Electron/Chromium). The selection has also collapsed, so a clipboard
        // ⌘V would append rather than replace → caller should hand off via clipboard.
        let valueAfter = axStringValue(element)
        let noOp = valueBefore != nil && valueAfter != nil && valueBefore == valueAfter

        // Secondary checks when kAXValueAttribute is unavailable (non-native apps).
        if !noOp, valueBefore == nil {
            var selectedAfterRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedAfterRef)
            let selectedAfter = selectedAfterRef as? String

            // Case A: selectedText was non-empty and is unchanged → definite no-op.
            if let before = selectedBefore, let after = selectedAfter, !before.isEmpty, before == after {
                insertLog.notice("replaceViaElement → ignored (selectedText unchanged)")
                return .ignored
            }

            // Case B: selection was empty/nil before AND after (focus-stole popup collapsed
            // the selection; the app also ignored the range-restore attempt). We cannot
            // confirm the write took effect. Pessimistically treat as .ignored so the caller
            // falls through to clipboard paste — better than silently losing the result.
            let emptyOrNil: (String?) -> Bool = { $0 == nil || $0 == "" }
            if emptyOrNil(selectedBefore) && emptyOrNil(selectedAfter) {
                insertLog.notice("replaceViaElement → ignored (unverifiable: selection collapsed, value attr unavailable)")
                return .ignored
            }
        }

        insertLog.notice("replaceViaElement → \(noOp ? "ignored" : "replaced", privacy: .public)")
        return noOp ? .ignored : .replaced
    }

    /// Reads the text currently occupying `range` via the parameterized
    /// AXStringForRange attribute. Returns nil when the app doesn't support it.
    private static func axString(for range: CFRange, in element: AXUIElement) -> String? {
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &out
        ) == .success else {
            return nil
        }
        return out as? String
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
        let valueBefore = axStringValue(element)

        // Secondary capture for apps that don't expose kAXValueAttribute.
        var selectedBeforeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedBeforeRef)
        let selectedBefore = selectedBeforeRef as? String

        let ok = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
        guard ok else { return false }

        // Primary check: if the full-value attribute is available and unchanged,
        // the write was a no-op (Electron/Chromium ignore AX text writes).
        let valueAfter = axStringValue(element)
        if let before = valueBefore, let after = valueAfter {
            if before == after {
                insertLog.notice("setSelectedText no-op (value unchanged)")
                return false
            }
            return true
        }

        // Secondary checks: kAXValueAttribute unavailable (non-native app).
        var selectedAfterRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedAfterRef)
        let selectedAfter = selectedAfterRef as? String

        // Case A: non-empty selection unchanged → definite no-op.
        if let before = selectedBefore, let after = selectedAfter, !before.isEmpty, before == after {
            insertLog.notice("setSelectedText no-op (selectedText unchanged)")
            return false
        }

        // Case B: both empty/nil → unverifiable (collapsed selection in non-native app).
        // Pessimistically return false to trigger clipboard paste.
        let emptyOrNil: (String?) -> Bool = { $0 == nil || $0 == "" }
        if emptyOrNil(selectedBefore) && emptyOrNil(selectedAfter) {
            insertLog.notice("setSelectedText no-op (unverifiable: selection collapsed, value attr unavailable)")
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
