import AppKit
import ApplicationServices
import Carbon

extension TextInsertion {
    enum CorrectionWrite: Equatable {
        case written, notWritten, unverified
    }

    /// No selection walk or simulated paste: a correction is bound to the captured
    /// text field, and the resulting field value must confirm the write.
    static func writeDictationCorrection(_ text: String, pid: pid_t, captured: AXUIElement) -> CorrectionWrite {
        guard let field = currentCorrectionField(pid: pid, captured: captured),
              let before = axStringValue(field), let range = FocusedFieldReader.selectedRange(field),
              let expected = expectedCorrectionValue(before: before, range: range, text: text),
              currentCorrectionField(pid: pid, captured: field) != nil else { return .notWritten }
        let status = AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        switch status {
        case .attributeUnsupported, .notImplemented, .illegalArgument, .actionUnsupported:
            return .notWritten
        default:
            guard currentCorrectionField(pid: pid, captured: field) != nil else { return .unverified }
            return correctionWriteResult(before: before, expected: expected, after: axStringValue(field),
                                         acknowledged: status == .success)
        }
    }

    private static func currentCorrectionField(pid: pid_t, captured: AXUIElement) -> AXUIElement? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, !IsSecureEventInputEnabled(),
              let field = FocusedFieldReader.focusedElement(pid: pid), CFEqual(field, captured),
              let role = FocusedFieldReader.string(field, kAXRoleAttribute),
              AutocompleteExclusion.textRoles.contains(role) else { return nil }
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(field, kAXSubroleAttribute as CFString, &value) {
        case .success:
            guard let subrole = value as? String, subrole != kAXSecureTextFieldSubrole as String else { return nil }
        case .attributeUnsupported, .noValue:
            break
        default:
            return nil
        }
        return field
    }

    nonisolated static func expectedCorrectionValue(before: String, range: CFRange, text: String) -> String? {
        let value = before as NSString
        guard range.location >= 0, range.length >= 0, range.location <= value.length,
              range.length <= value.length - range.location else { return nil }
        return value.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
    }

    nonisolated static func correctionWriteResult(before: String, expected: String, after: String?,
                                                  acknowledged: Bool) -> CorrectionWrite {
        guard let after else { return .unverified }
        if acknowledged, after == expected { return .written }
        return after == before ? .notWritten : .unverified
    }
}
