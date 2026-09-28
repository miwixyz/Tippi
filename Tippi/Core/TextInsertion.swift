import AppKit
import ApplicationServices
import os

private let insertLog = Logger(subsystem: "com.tippi.app", category: "insert")

@MainActor
enum TextInsertion {
    /// A captured target must not silently fall through to the app that happens
    /// to be focused after the AI request. `nil` means there was no captured
    /// target and the current focus is intentionally the destination.
    nonisolated static func isExpectedFrontmost(targetPID: pid_t?, frontmostPID: pid_t?) -> Bool {
        guard let targetPID else { return true }
        return targetPID == frontmostPID
    }

    static func replace(with text: String, in app: NSRunningApplication?) async {
        if let app, replaceSelectionViaAccessibility(with: text, in: app) {
            insertLog.notice("AX replace ok (\(text.count) chars)")
            return
        }
        if app == nil, replaceSelectionViaAccessibility(with: text) {
            insertLog.notice("AX replace (focused) ok")
            return
        }

        insertLog.notice("AX replace failed → clipboard+paste fallback")
        if let app { await TextCapture.activateAndWaitForFocus(app) }
        await paste(text: text, expectedPID: app?.processIdentifier)
    }

    static func replace(with attributedText: NSAttributedString, fallbackPlainText: String, in app: NSRunningApplication?) async {
        if let app, replaceSelectionViaAccessibility(with: fallbackPlainText, in: app) {
            return
        }
        if app == nil, replaceSelectionViaAccessibility(with: fallbackPlainText) {
            return
        }

        if let app { await TextCapture.activateAndWaitForFocus(app) }
        await paste(attributedText: attributedText, fallbackPlainText: fallbackPlainText,
                    expectedPID: app?.processIdentifier)
    }

    /// Re-selects `range` on `element` and reads it back. `nil` means the
    /// selection is in place; otherwise the outcome explains why not. Shared by
    /// `replaceViaElement` and `pasteFormatting` — both must never write into a
    /// selection that did not take (see the comment at the call site).
    private static func restoreSelection(_ element: AXUIElement, range: CFRange) -> AXReplaceOutcome? {
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else {
            insertLog.notice("replaceViaElement → unavailable (could not build AX range)")
            return .unavailable
        }
        let rangeSet = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard rangeSet == .success else {
            insertLog.notice(
                "replaceViaElement → ignored (app refused range restore, set=\(rangeSet.rawValue, privacy: .public)) — not writing, a write here would append")
            return .ignored
        }

        // Read the range back. A success status only means the app accepted the
        // message, not that the selection actually moved; Electron-based apps
        // answer .success and keep a collapsed caret.
        var verifyRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &verifyRef) == .success,
           let verifyValue = verifyRef, CFGetTypeID(verifyValue) == AXValueGetTypeID() {
            var actual = CFRange()
            // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
            if AXValueGetValue(verifyValue as! AXValue, .cfRange, &actual),
               actual.length != range.length {
                insertLog.notice(
                    "replaceViaElement → ignored (selection did not take: asked for len \(range.length, privacy: .public), got \(actual.length, privacy: .public))")
                return .ignored
            }
        }
        return nil
    }

    /// Formatting-only change (highlight): same characters, new attributes.
    ///
    /// Never writes plain text via Accessibility first. Writing the identical
    /// text collapses the selection in native apps while the value stays the
    /// same, the write reads as a no-op, and the paste that follows lands after
    /// the text as a second copy. Instead: restore the captured range (the
    /// hotkey popup collapsed the live selection), then paste the rich text
    /// over it. If the range cannot be restored nothing is written — a missing
    /// highlight beats a duplicate.
    static func pasteFormatting(_ attributedText: NSAttributedString, fallbackPlainText: String,
                                element: AXUIElement?, range: CFRange?,
                                app: NSRunningApplication?) async {
        if let element, let range {
            guard AXIsProcessTrusted(), restoreSelection(element, range: range) == nil else {
                insertLog.notice("pasteFormatting → skipped (selection could not be restored)")
                return
            }
        }
        if let app { await TextCapture.activateAndWaitForFocus(app) }
        await paste(attributedText: attributedText, fallbackPlainText: fallbackPlainText,
                    expectedPID: app?.processIdentifier)
    }

    /// Inserts a secret (generated password) at the cursor of `app`.
    ///
    /// Paste only, deliberately without the Accessibility write first: in apps
    /// that do not expose their value that write is "unverifiable", the ladder
    /// then pastes as well, and a doubled password is not something the user
    /// would notice. Password fields hide their value anyway. The clipboard
    /// copy is host-only (no Handoff), concealed from clipboard managers and
    /// replaced by the previous contents right after the paste.
    ///
    /// The secret then stays on the clipboard for `secretClipboardLifetime`
    /// (Michael, 2026-09-28: "Passwort wiederholen" fields need a second ⌘V),
    /// after which the previous clipboard comes back — unless something else
    /// was copied meanwhile, which `PasteboardSnapshot.restore` never overwrites.
    static func insertSecret(_ text: String, into app: NSRunningApplication?) async {
        if let app { await TextCapture.activateAndWaitForFocus(app) }
        let snapshot = await paste(text: text, expectedPID: app?.processIdentifier,
                                   currentHostOnly: true, restoreClipboard: false)
        insertLog.notice("secret pasted (\(text.count, privacy: .public) chars), clipboard cleared in \(Int(secretClipboardLifetime), privacy: .public) s")
        Task {
            try? await Task.sleep(nanoseconds: UInt64(secretClipboardLifetime * 1_000_000_000))
            snapshot.restore()
            insertLog.notice("secret clipboard lifetime over — previous clipboard restored if untouched")
        }
    }

    static let secretClipboardLifetime: TimeInterval = 60

    /// Bypasses AX entirely and inserts `text` via clipboard + synthetic ⌘V.
    /// Use when AX has already been attempted and confirmed to be a no-op
    /// (e.g. `.ignored` outcome from `replaceViaElement`).
    static func insertViaClipboard(_ text: String, into app: NSRunningApplication?) async {
        if let app { await TextCapture.activateAndWaitForFocus(app) }
        await paste(text: text, expectedPID: app?.processIdentifier)
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

    /// Returns the snapshot of the previous clipboard. With `restoreClipboard`
    /// false the caller decides when to put it back (`insertSecret`).
    @discardableResult
    private static func paste(text: String, expectedPID: pid_t?, currentHostOnly: Bool = false,
                              restoreClipboard: Bool = true) async -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        var snapshot = PasteboardSnapshot.capture()

        if currentHostOnly {
            // Keeps the content off Universal Clipboard (Handoff to iPhone/iPad);
            // same measure as the screen-OCR result. Also clears the contents.
            pb.prepareForNewContents(with: .currentHostOnly)
        } else {
            pb.clearContents()
        }
        pb.setString(text, forType: .string)
        pb.setString("", forType: concealedType)
        snapshot.markOwnedChange(on: pb)

        try? await Task.sleep(nanoseconds: 40_000_000)
        guard isExpectedFrontmost(targetPID: expectedPID,
                                  frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            // Do not post ⌘V into a different app. The result stays on the
            // clipboard for manual recovery instead of replacing unrelated text.
            insertLog.error("paste withheld: target app is no longer frontmost")
            return snapshot
        }
        simulatePaste()
        try? await Task.sleep(nanoseconds: 400_000_000)

        if restoreClipboard { snapshot.restore() }
        return snapshot
    }

    private static func paste(attributedText: NSAttributedString, fallbackPlainText: String,
                              expectedPID: pid_t?) async {
        let pb = NSPasteboard.general
        var snapshot = PasteboardSnapshot.capture()

        pb.clearContents()
        if let rtf = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(fallbackPlainText, forType: .string)
        pb.setString("", forType: concealedType)
        snapshot.markOwnedChange(on: pb)

        try? await Task.sleep(nanoseconds: 40_000_000)
        guard isExpectedFrontmost(targetPID: expectedPID,
                                  frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            insertLog.error("rich paste withheld: target app is no longer frontmost")
            return
        }
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

        // Restoring the range is not optional bookkeeping — it decides whether
        // the write below *replaces* or *inserts*. Setting kAXSelectedText
        // overwrites the current selection; with no selection it inserts at the
        // caret. So if an app declines the range restore, writing anyway
        // appends the transformed text next to the original instead of
        // replacing it. That is the doubling reported on 2026-09-14
        // ("Wichtig ist nurWichtig ist nur"), and the old code could not see it
        // coming because it discarded this result and then judged success by
        // "did the value change at all" — which appending satisfies.
        if let failure = restoreSelection(element, range: range) {
            return failure
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
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        if let focused = focusedElement(in: appElement),
           setSelectedText(text, on: focused) {
            return true
        }

        // Depth alone does not bound a broad Electron/Xcode accessibility tree.
        // Share one deadline across all windows and cap each synchronous IPC.
        let deadline = CFAbsoluteTimeGetCurrent() + 0.4
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let element = findElementWithSelection(in: window, depth: 0, deadline: deadline),
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
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRaw = focusedRef,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return false
        }

        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        return setSelectedText(text, on: focusedRaw as! AXUIElement)
    }

    private static func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.25)
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

    nonisolated static func shouldContinueAXWalk(depth: Int, now: CFAbsoluteTime,
                                                 deadline: CFAbsoluteTime) -> Bool {
        depth <= 14 && now < deadline
    }

    private static func findElementWithSelection(in element: AXUIElement, depth: Int,
                                                 deadline: CFAbsoluteTime) -> AXUIElement? {
        guard shouldContinueAXWalk(depth: depth, now: CFAbsoluteTimeGetCurrent(), deadline: deadline) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.25)

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
            if let match = findElementWithSelection(in: child, depth: depth + 1, deadline: deadline) {
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
        ) == .success, let focusedRaw = focusedRef,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        return (focusedRaw as! AXUIElement)
    }

    /// Synthetic Return, used after a dictation in apps the user opted in
    /// (`DictationSettings.autoReturnBundleIDs`). Flags are cleared explicitly:
    /// a modifier still held from the dictation gesture would otherwise turn it
    /// into ⇧↩ — a line break instead of "send" in chat apps.
    static func pressReturn() {
        let src = CGEventSource(stateID: .hidSystemState)
        let returnKey: CGKeyCode = 36 // kVK_Return

        let down = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: true)
        down?.flags = []
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: false)
        up?.flags = []
        up?.post(tap: .cghidEventTap)
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
