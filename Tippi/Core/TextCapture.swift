import AppKit
import ApplicationServices

struct CapturedText {
    let text: String
    let sourceApp: NSRunningApplication?
    let usedClipboardFallback: Bool
}

@MainActor
enum TextCapture {
    static func captureSelectedText(sourceApp: NSRunningApplication?) async -> CapturedText? {
        let app = resolvedSourceApp(sourceApp)
        NSLog("Tippi: TextCapture app=\(app?.localizedName ?? "nil") trusted=\(AXIsProcessTrusted())")

        // Phase 1: do not activate — front app still owns the selection (right after hotkey).
        if let text = await readViaPasteboard(), !text.isEmpty {
            NSLog("Tippi: TextCapture pasteboard (no activate) ok (\(text.count) chars)")
            return CapturedText(text: text, sourceApp: app, usedClipboardFallback: true)
        }
        if let app, let text = readViaAccessibility(in: app), !text.isEmpty {
            NSLog("Tippi: TextCapture AX (no activate) ok (\(text.count) chars)")
            return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
        }
        if let app, let text = readViaSystemEvents(in: app), !text.isEmpty {
            NSLog("Tippi: TextCapture System Events (no activate) ok (\(text.count) chars)")
            return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
        }

        // Phase 2: activate source app and retry.
        if let app {
            app.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 150_000_000)

            if let text = readViaAccessibility(in: app), !text.isEmpty {
                NSLog("Tippi: TextCapture AX ok (\(text.count) chars)")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
            }
            if let text = readViaSystemEvents(in: app), !text.isEmpty {
                NSLog("Tippi: TextCapture System Events ok (\(text.count) chars)")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: false)
            }
            if let text = await readViaAccessibilityCopyAction(in: app), !text.isEmpty {
                NSLog("Tippi: TextCapture AXCopy ok (\(text.count) chars)")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: true)
            }
            if let text = await readViaPasteboard(), !text.isEmpty {
                NSLog("Tippi: TextCapture pasteboard ok (\(text.count) chars)")
                return CapturedText(text: text, sourceApp: app, usedClipboardFallback: true)
            }
        }

        NSLog("Tippi: TextCapture failed")
        return nil
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

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let text = findSelectedText(in: window, depth: 0), !text.isEmpty {
                    return text
                }
            }
        }

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowRaw = windowRef {
            return findSelectedText(in: windowRaw as! AXUIElement, depth: 0)
        }

        return nil
    }

    private static func readViaAccessibilityCopyAction(in app: NSRunningApplication) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = focusedElement(in: appElement) else { return nil }

        let snapshot = PasteboardSnapshot.capture()
        let status = AXUIElementPerformAction(focused, "AXCopy" as CFString)
        guard status == .success else {
            snapshot.restore()
            return nil
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        let text = NSPasteboard.general.string(forType: .string)
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
        ) == .success, let focusedRaw = focusedRef else {
            return nil
        }
        return (focusedRaw as! AXUIElement)
    }

    static func findSelectedText(in element: AXUIElement, depth: Int) -> String? {
        guard depth <= 14 else { return nil }

        if let text = selectedText(from: element), !text.isEmpty {
            return text
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let text = findSelectedText(in: child, depth: depth + 1) {
                return text
            }
        }
        return nil
    }

    private static func selectedText(from element: AXUIElement) -> String? {
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

    private static func readViaSystemEvents(in app: NSRunningApplication) -> String? {
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

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        let result = appleScript.executeAndReturnError(&error)
        if error != nil { return nil }
        let text = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    // MARK: - Pasteboard

    private static func readViaPasteboard() async -> String? {
        let snapshot = PasteboardSnapshot.capture()
        simulateCopy()
        try? await Task.sleep(nanoseconds: 120_000_000)

        let captured = NSPasteboard.general.string(forType: .string)?
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
