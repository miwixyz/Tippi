import AppKit
import ApplicationServices
import os

private let captureLog = Logger(subsystem: "com.tippi.app", category: "capture")

struct CapturedText {
    let text: String
    let sourceApp: NSRunningApplication?
    let usedClipboardFallback: Bool
}

@MainActor
enum TextCapture {
    /// Activates `app` and waits until it actually becomes frontmost, polling in
    /// short steps with an early exit. Snappy apps return in ~15–30 ms instead
    /// of a flat 150 ms wait; sluggish/non-cooperating apps are capped at
    /// ~300 ms so we never stall. Shared by capture and insertion.
    static func activateAndWaitForFocus(_ app: NSRunningApplication) async {
        app.activate()
        for _ in 0..<20 {  // up to ~300 ms, exits as soon as the app is active
            if app.isActive { return }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    static func captureSelectedText(sourceApp: NSRunningApplication?) async -> CapturedText? {
        let app = resolvedSourceApp(sourceApp)
        captureLog.notice("capture start app=\(app?.localizedName ?? "nil", privacy: .public) trusted=\(AXIsProcessTrusted())")

        // Phase 1: do not activate — front app still owns the selection (right after hotkey).
        if let text = await readViaPasteboard(), !text.isEmpty {
            captureLog.notice("pasteboard (no activate) ok \(text.count) chars")
            return CapturedText(text: text, sourceApp: app, usedClipboardFallback: true)
        }
        if let app, let text = readViaAccessibility(in: app), !text.isEmpty {
            captureLog.notice("AX (no activate) ok \(text.count) chars")
            return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
        }
        if let app, let text = await readViaSystemEvents(in: app), !text.isEmpty {
            captureLog.notice("System Events (no activate) ok \(text.count) chars")
            return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
        }

        // Phase 2: activate source app and retry.
        if let app {
            await activateAndWaitForFocus(app)

            if let text = readViaAccessibility(in: app), !text.isEmpty {
                captureLog.notice("AX ok \(text.count) chars")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
            }
            if let text = await readViaSystemEvents(in: app), !text.isEmpty {
                captureLog.notice("System Events ok \(text.count) chars")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
            }
            if let text = await readViaAccessibilityCopyAction(in: app), !text.isEmpty {
                captureLog.notice("AXCopy ok \(text.count) chars")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: true)
            }
            if let text = await readViaPasteboard(), !text.isEmpty {
                captureLog.notice("pasteboard ok \(text.count) chars")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: true)
            }
        }

        captureLog.notice("capture FAILED")
        return nil
    }

    /// Grabs the focused text element + its current selection range while the selection
    /// is still live (before the popup steals focus). Used to re-select and replace
    /// after a local quick action, since the popup collapses the source app's selection.
    static func captureFocusedSelectionRange(
        in app: NSRunningApplication
    ) -> (element: AXUIElement, range: CFRange)? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = focusedElement(in: appElement) else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeValue = rangeRef else {
            return nil
        }

        var range = CFRange()
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
              AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0 else {
            return nil
        }
        return (focused, range)
    }

    /// On-screen bounds of a selection range, for positioning the selection
    /// action bar next to it. Returns AppKit screen coordinates (origin
    /// bottom-left, Y increasing upward) — `kAXBoundsForRangeParameterizedAttribute`
    /// itself reports Quartz/AX coordinates (origin top-left, Y increasing
    /// downward, relative to the primary screen), so this converts before
    /// returning. Not every app implements this parameterized attribute
    /// (same class of app as the ones that don't expose `kAXValueAttribute`
    /// for writes, per `TextInsertion`'s comments) — nil means "no bounds
    /// available", the caller falls back to the mouse position instead.
    static func boundsForSelection(element: AXUIElement, range: CFRange) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsRef
        ) == .success, let boundsValue = boundsRef, CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var axRect = CGRect.zero
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axRect) else { return nil }

        // AX/Quartz coordinates are anchored to the primary screen's top-left
        // corner, Y growing downward. `NSScreen.screens[0]` is always that
        // primary screen (the one the coordinate system originates from),
        // regardless of which physical display is "main" for window
        // placement — using its height is what makes this conversion correct
        // across multi-monitor setups, not just the single-display case.
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return nil }
        let flippedY = primaryScreenHeight - axRect.origin.y - axRect.height
        return CGRect(x: axRect.origin.x, y: flippedY, width: axRect.width, height: axRect.height)
    }

    private static func resolvedSourceApp(_ sourceApp: NSRunningApplication?) -> NSRunningApplication? {
        if let sourceApp, sourceApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            return sourceApp
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return sourceApp
    }

    // MARK: - Accessibility

    private static func readViaAccessibility(in app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        if let focused = focusedElement(in: appElement),
           let text = selectedText(from: focused), !text.isEmpty {
            return text
        }

        // One deadline for the whole sweep, not one per window — otherwise a
        // ten-window app gets ten separate budgets and the cap means nothing.
        let deadline = CFAbsoluteTimeGetCurrent() + axWalkBudget

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let text = findSelectedText(in: window, depth: 0, deadline: deadline), !text.isEmpty {
                    return text
                }
            }
        }

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowRaw = windowRef, CFGetTypeID(windowRaw) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
            return findSelectedText(in: windowRaw as! AXUIElement, depth: 0, deadline: deadline)
        }

        return nil
    }

    private static func readViaAccessibilityCopyAction(in app: NSRunningApplication) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = focusedElement(in: appElement) else { return nil }

        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()
        // `AXCopy` returning `.success` only means the app accepted the action,
        // not that it wrote anything. Some apps acknowledge it and copy
        // nothing — then the clipboard still holds whatever the user copied
        // earlier, and handing that back would send unrelated content (the
        // password or TAN they copied a minute ago) to the LLM provider and
        // paste the result over their selection. `changeCount` is the only
        // proof that a copy actually happened; `readViaPasteboard` below has
        // always taken it, this path never did. Found by audit 2026-09-19.
        let beforeCount = pb.changeCount
        let status = AXUIElementPerformAction(focused, "AXCopy" as CFString)
        guard status == .success else {
            snapshot.restore()
            return nil
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard pb.changeCount != beforeCount else {
            captureLog.debug("AXCopy reported success but the pasteboard did not change — refusing stale clipboard content")
            snapshot.restore()
            return nil
        }
        let text = pb.string(forType: .string)
        snapshot.restore()
        guard let text, !text.isEmpty else { return nil }
        return text
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

    /// How long the whole accessibility walk may take before it gives up.
    ///
    /// The depth cap alone does not bound the work: the walk visits *every*
    /// window and every child down to depth 14, and each step is a synchronous
    /// AX IPC call on the main actor. `AXUIElementSetMessagingTimeout` caps a
    /// single call at 2 s, not their sum — so a wide tree (Electron, a large
    /// Xcode project) freezes Tippi's menu bar and every panel for as long as
    /// the walk runs, and on the failure path the walk happens twice per
    /// hotkey press. Confirmed as the most severe finding of the 2026-09-19
    /// audit.
    ///
    /// 400 ms is chosen against the alternative, which is not "a complete
    /// answer" but "an unbounded freeze": this path is already the fallback
    /// that runs only after the pasteboard route found nothing, and giving up
    /// leaves the field empty — the same outcome as no selection, which the
    /// callers already handle.
    private static let axWalkBudget: CFTimeInterval = 0.4

    static func findSelectedText(in element: AXUIElement, depth: Int) -> String? {
        findSelectedText(in: element, depth: depth, deadline: CFAbsoluteTimeGetCurrent() + axWalkBudget)
    }

    private static func findSelectedText(in element: AXUIElement, depth: Int, deadline: CFAbsoluteTime) -> String? {
        guard depth <= 14 else { return nil }
        guard CFAbsoluteTimeGetCurrent() < deadline else {
            // Never give up silently — without this line a truncated walk is
            // indistinguishable from "nothing was selected".
            captureLog.debug("accessibility walk hit its \(axWalkBudget, privacy: .public)s budget at depth \(depth, privacy: .public) — giving up rather than blocking the main actor")
            return nil
        }

        if let text = selectedText(from: element), !text.isEmpty {
            return text
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let text = findSelectedText(in: child, depth: depth + 1, deadline: deadline) {
                return text
            }
        }
        return nil
    }

    /// Reads the selected text directly off a specific element — used when
    /// the caller already has a live `(element, range)` pair (from
    /// `captureFocusedSelectionRange`) and doesn't need the broader
    /// app-wide search `captureSelectedText` does.
    static func selectedText(from element: AXUIElement) -> String? {
        if let direct = copyStringAttribute(element, kAXSelectedTextAttribute as CFString),
           !direct.isEmpty {
            return direct
        }
        return stringForSelectedRange(on: element)
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success else { return nil }
        return valueRef as? String
    }

    private static func stringForSelectedRange(on element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeValue = rangeRef else {
            return nil
        }

        var textRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &textRef
        ) == .success else {
            return nil
        }
        return textRef as? String
    }

    // MARK: - System Events

    private static func readViaSystemEvents(in app: NSRunningApplication) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let processName = (app.localizedName ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        guard !processName.isEmpty else { return nil }

        let script = """
        tell application "System Events"
            if not (exists process "\(processName)") then return ""
            tell process "\(processName)"
                try
                    return value of attribute "AXSelectedText" of (first UI element whose focused is true)
                on error
                    try
                        return value of attribute "AXSelectedText" of (first text area whose focused is true)
                    on error
                        return ""
                    end try
                end try
            end tell
        end tell
        """

        // NSAppleScript compile+execute is synchronous and can block for hundreds
        // of ms when System Events scripts an unresponsive/large target app.
        // Because TextCapture is @MainActor, running it inline would freeze the
        // whole UI (menubar + popup) during that time. Run it off the main actor.
        return await Task.detached(priority: .userInitiated) { () -> String? in
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else { return nil }
            let result = appleScript.executeAndReturnError(&error)
            if error != nil { return nil }
            let text = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }.value
    }

    // MARK: - Pasteboard

    private static func readViaPasteboard() async -> String? {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()
        let beforeCount = pb.changeCount
        simulateCopy()
        try? await Task.sleep(nanoseconds: 120_000_000)

        // A real ⌘C always bumps changeCount. If it didn't change, nothing was
        // selected or the app ignored the synthetic ⌘C (common in Electron/Chromium) —
        // returning the unchanged clipboard would hand back stale, unrelated content.
        guard pb.changeCount != beforeCount else {
            snapshot.restore()
            captureLog.notice("pasteboard: changeCount unchanged — synthetic ⌘C produced no copy")
            return nil
        }

        let captured = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.restore()

        guard let captured, !captured.isEmpty else { return nil }
        return captured
    }

    private static func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cKey: CGKeyCode = 8 // C

        for tap in [CGEventTapLocation.cghidEventTap, .cgAnnotatedSessionEventTap] {
            let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: tap)

            let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: tap)
        }
    }
}
