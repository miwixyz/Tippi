import AppKit
import ApplicationServices
import os

private let pasteLog = Logger(subsystem: "com.tippi.app", category: "insert")

/// Makes the clipboard fallback (`paste`) wait for the target field and check
/// that the ⌘V actually arrived.
///
/// Anlass 2026-10-30: In Apple Mail ignoriert das Schreibfeld jeden
/// Accessibility-Schreibversuch, das Ergebnis geht also immer über
/// Zwischenablage + synthetisches ⌘V. Das kam manchmal nicht an — Fenster zu,
/// nichts passiert. Protokoll für Erfolg und Fehlschlag war identisch, weil der
/// alte Weg nur „aktiv?“ prüfte (dann 40 ms) und das Ergebnis nicht ansah.
/// Nach 0,4 s lag zudem schon wieder die alte Zwischenablage drin, ein
/// eigenes ⌘V half also auch nicht mehr.
extension TextInsertion {
    enum PasteOutcome: Equatable {
        /// The focused field's value changed after the ⌘V.
        case landed
        /// The value was readable and stayed the same — the ⌘V went nowhere.
        case notLanded
        /// The field does not expose its value; nothing can be said.
        case unknown
    }

    /// What `paste` knows about the destination right before the ⌘V.
    struct PasteTarget {
        let element: AXUIElement?
        let valueBefore: String?
        let focusWaitMs: Int
        let role: String
    }

    /// Longest wait for the field before ⌘V, and for its effect after.
    static let focusWaitLimit: TimeInterval = 1.0
    static let pasteEffectLimit: TimeInterval = 1.0

    nonisolated static func pasteOutcome(before: String?, after: String?) -> PasteOutcome {
        guard let before, let after else { return .unknown }
        return before == after ? .notLanded : .landed
    }

    /// Waits until `pid` has a focused element that takes text (its selected
    /// range is readable), at most `focusWaitLimit`. Returns immediately in the
    /// normal case; only a slow app such as Mail right after Tippi's window
    /// closed makes it wait.
    static func preparePasteTarget(pid: pid_t?) async -> PasteTarget {
        guard let pid, AXIsProcessTrusted() else {
            return PasteTarget(element: nil, valueBefore: nil, focusWaitMs: 0, role: "n/a")
        }
        let start = CFAbsoluteTimeGetCurrent()
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        var element: AXUIElement?
        while true {
            if let focused = focusedElement(in: appElement), takesText(focused) {
                element = focused
                break
            }
            if CFAbsoluteTimeGetCurrent() - start >= focusWaitLimit { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let waited = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        return PasteTarget(element: element,
                           valueBefore: element.flatMap(axStringValue),
                           focusWaitMs: waited,
                           role: element.flatMap(role(of:)) ?? "none")
    }

    /// Polls the field after the ⌘V until its value changes, at most
    /// `pasteEffectLimit`. Without a readable value it simply waits the full
    /// time, so the clipboard is not restored before a slow app has read it.
    static func awaitPasteEffect(on target: PasteTarget) async -> (PasteOutcome, Int) {
        let start = CFAbsoluteTimeGetCurrent()
        var outcome = PasteOutcome.unknown
        while CFAbsoluteTimeGetCurrent() - start < pasteEffectLimit {
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard let element = target.element, target.valueBefore != nil else { continue }
            outcome = pasteOutcome(before: target.valueBefore, after: axStringValue(element))
            if outcome == .landed { break }
        }
        return (outcome, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    /// Messpunkt: only lengths, times and roles, never text — hence public.
    static func logPasteCheck(_ target: PasteTarget, outcome: PasteOutcome, effectMs: Int) {
        pasteLog.notice(
            "paste check: focus=\(target.element == nil ? "missing" : "found", privacy: .public) wait=\(target.focusWaitMs, privacy: .public)ms role=\(target.role, privacy: .public) value=\(target.valueBefore == nil ? "unreadable" : "readable", privacy: .public) → \(String(describing: outcome), privacy: .public) after \(effectMs, privacy: .public)ms")
    }

    /// The ⌘V provably went nowhere: keep the result on the clipboard and say so,
    /// instead of putting the old clipboard back and losing the text.
    static func reportPasteNotLanded() {
        pasteLog.error("paste not landed — result kept on the clipboard")
        ToastWindowController.shared.show(message: String(localized: "insert.toast.pasteNotLanded"), seconds: 4)
    }

    private static func takesText(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var rangeRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success
    }

    private static func role(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }
}
