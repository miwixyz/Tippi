import AppKit
import Carbon
import os

private let insertLog = Logger(subsystem: "com.tippi.app", category: "insert-fit")

/// The last step of a dictation: write the text where it belongs, fitted to
/// the text at the cursor (`InsertionFitter`) and only into the field that had
/// the focus when the recording ended (`FieldFingerprint`). Out of
/// `DictationController.swift` (SwiftLint `file_length`).
///
extension DictationController {
    struct CorrectionDraft {
        let text: String
        let excerpt: String
    }

    struct InsertionOutcome {
        var notice: String?
        var excerpt: String?
    }

    /// Corrections follow cleanup so stored phrases never feed a provider.
    /// Both they and layout skip targets where Return can execute or send text.
    func prepareInsertion(_ polished: String, targetID: String?, isNotes: Bool) -> (String, CorrectionDraft?) {
        let targetExcluded = targetID.map(Self.excludesCorrections) ?? false
        let layout = DictationLayout.layoutWanted(source: source, toggle: DictationSettings.layoutEnabled,
                                                   targetIsTerminal: targetExcluded)
        let original = layout ? DictationLayout.format(polished) : polished
        let corrections = DictationCorrections.shared
        guard corrections.enabled, source == .standard, !targetExcluded, isNotes || targetID != nil else {
            return (original, nil)
        }
        let corrected = corrections.apply(to: polished)
        let final = corrected == polished ? original : (layout ? DictationLayout.format(corrected) : corrected)
        return (original, CorrectionDraft(text: final, excerpt: polished))
    }

    private static func excludesCorrections(_ targetID: String) -> Bool {
        DictationSettings.commandCapableBundleIDs.contains(targetID) || DictationSettings.autoReturnBundleIDs.contains(targetID)
    }

    static func insert(_ text: String, correction: CorrectionDraft?, intoNotes textView: NSTextView,
                       fit: Bool) -> InsertionOutcome {
        // The Notes window is kept (not released) when closed, so
        // `window != nil` proves nothing — visibility does. Closed
        // meanwhile: clipboard, never a background app.
        guard let window = textView.window, window.isVisible else {
            TextInsertion.copy(text)
            return InsertionOutcome(notice: String(localized: "dictation.toast.notesClosedCopied"))
        }
        let eligible = window.isKeyWindow && window.firstResponder === textView
            && !IsSecureEventInputEnabled() && DictationCorrections.shared.enabled
        let correction = eligible ? correction : nil
        let range = textView.selectedRange()
        let field = fit
            ? FocusedFieldReader.slice(textView.string, range: CFRange(location: range.location, length: range.length))
            : nil
        let fitted = InsertionFitter.fit(correction?.text ?? text, around: field)
        guard ReplacementWriter.writeNative(fitted, in: textView, range: range) else {
            return InsertionOutcome(notice: String(localized: "dictation.toast.correctionWriteUnverified"))
        }
        return InsertionOutcome(excerpt: correction?.excerpt)
    }

    static func insert(_ text: String, correction: CorrectionDraft?, into targetApp: NSRunningApplication?,
                       targetField: FocusedFieldReader.FocusSpot?, fit: Bool) async -> InsertionOutcome {
        // Same app, other field: never write there. Only a proven different
        // field counts; an app that doesn't tell gets the text as before.
        if let targetField, let pid = targetApp?.processIdentifier,
           let now = FocusedFieldReader.focusSpot(pid: pid, textFieldOnly: false),
           !now.isSameField(as: targetField) {
            TextInsertion.copy(text)
            NSLog("Tippi: dictation not inserted — focus moved to another field (\(now.fingerprint.role ?? "?"))")
            return InsertionOutcome(notice: String(localized: "dictation.toast.fieldChangedCopied"))
        }
        // Read right before writing: that is where the text actually goes.
        let field = fit ? targetApp.flatMap { FocusedFieldReader.text(pid: $0.processIdentifier) } : nil
        if let correction, let targetApp, let targetField, let id = targetApp.bundleIdentifier,
           DictationCorrections.shared.enabled, !excludesCorrections(id) {
            let corrected = InsertionFitter.fit(correction.text, around: field)
            switch TextInsertion.writeDictationCorrection(corrected, pid: targetApp.processIdentifier,
                                                          captured: targetField.element) {
            case .written:
                return InsertionOutcome(excerpt: correction.excerpt)
            case .unverified:
                return InsertionOutcome(notice: String(localized: "dictation.toast.correctionWriteUnverified"))
            case .notWritten:
                break
            }
        }
        let fitted = InsertionFitter.fit(text, around: field)
        logFit(fit: fit, field: field, original: text, fitted: fitted)
        await TextInsertion.replace(with: fitted, in: targetApp)
        return InsertionOutcome()
    }

    /// Messpunkt (Sichttest 2026-10-27: „wird.Bitte“ ohne Leerzeichen): ob das Feld
    /// lesbar war und was die Regeln geändert haben. Nur Längen und die Art des
    /// letzten Zeichens vor dem Cursor, nie Text — deshalb öffentlich.
    private static func logFit(fit: Bool, field: FieldText?, original: String, fitted: String) {
        let lastKind: String
        switch field?.before.last {
        case nil: lastKind = "none"
        case let char? where char.isNewline: lastKind = "newline"
        case let char? where char.isWhitespace: lastKind = "space"
        case let char? where char.isLetter || char.isNumber: lastKind = "word"
        default: lastKind = "punct"
        }
        insertLog.info("""
            fit wanted=\(fit, privacy: .public) field=\(field == nil ? "nil" : "read", privacy: .public) \
            before=\(field?.before.count ?? -1, privacy: .public) after=\(field?.after.count ?? -1, privacy: .public) \
            last=\(lastKind, privacy: .public) leadingSpaceAdded=\(fitted.hasPrefix(" ") && !original.hasPrefix(" "), privacy: .public) \
            changed=\(fitted != original, privacy: .public)
            """)
    }
}
