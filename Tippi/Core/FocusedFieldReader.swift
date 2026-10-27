import AppKit
import ApplicationServices

/// Reads the focused text field of an app through Accessibility — only what a
/// dictation needs to fit in (2026-10-27). Password fields are never read.
/// Every call carries a short timeout, so a hanging app cannot hold up the
/// insertion. Adapted from Blitztext's `FocusedFieldReader` (MIT, NOTICES.md);
/// Tippi sets the timeout per element instead of system-wide, so the
/// insertion code's own timeouts stay as they are.
@MainActor
enum FocusedFieldReader {
    /// Characters kept on each side of the cursor — the fitter looks at the
    /// last two characters before and the first word after.
    static let beforeLimit = 200
    static let afterLimit = 100
    private static let timeout: Float = 0.25

    /// Text before and after the cursor (selection left out) in the focused
    /// field of `pid`. Nil when Accessibility is not granted, the field is a
    /// password field, or it does not report its text and cursor.
    static func text(pid: pid_t) -> FieldText? {
        guard let focused = focusedElement(pid: pid), !isSecure(focused),
              let value = string(focused, kAXValueAttribute),
              let range = selectedRange(focused) else { return nil }
        return slice(value, range: range)
    }

    /// Pure part of `text(pid:)`: cuts `value` around an AX selection range
    /// (UTF-16 offsets, as AX reports them). Nil for a range outside the text.
    nonisolated static func slice(_ value: String, range: CFRange) -> FieldText? {
        let text = value as NSString
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.length else {
            return nil
        }
        return FieldText(
            before: String(text.substring(to: range.location).suffix(beforeLimit)),
            after: String(text.substring(from: range.location + range.length).prefix(afterLimit))
        )
    }

    // MARK: - Accessibility helpers

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let focused = element(app, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, timeout)
        return focused
    }

    /// Native and web password fields report the secure subrole; some apps
    /// report it as the role (the autocomplete checks the role, see
    /// `AutocompleteLogic.secureTextFieldRole`). Either one: hands off.
    static func isSecure(_ element: AXUIElement) -> Bool {
        let secure = kAXSecureTextFieldSubrole as String
        return string(element, kAXSubroleAttribute) == secure || string(element, kAXRoleAttribute) == secure
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        return (raw as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
