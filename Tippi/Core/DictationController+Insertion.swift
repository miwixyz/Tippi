import AppKit
import os

private let insertLog = Logger(subsystem: "com.tippi.app", category: "insert-fit")

/// The last step of a dictation: write the text where it belongs, fitted to
/// the text at the cursor (`InsertionFitter`) and only into the field that had
/// the focus when the recording ended (`FieldFingerprint`). Out of
/// `DictationController.swift` (SwiftLint `file_length`).
///
/// Both return nil when the text was written, otherwise the toast for "copied
/// to the clipboard instead".
extension DictationController {
    static func insert(_ text: String, intoNotes textView: NSTextView, fit: Bool) -> String? {
        // The Notes window is kept (not released) when closed, so
        // `window != nil` proves nothing — visibility does. Closed
        // meanwhile: clipboard, never a background app.
        guard textView.window?.isVisible == true else {
            TextInsertion.copy(text)
            return String(localized: "dictation.toast.notesClosedCopied")
        }
        let range = textView.selectedRange()
        let field = fit
            ? FocusedFieldReader.slice(textView.string, range: CFRange(location: range.location, length: range.length))
            : nil
        ReplacementWriter.writeNative(InsertionFitter.fit(text, around: field), in: textView, range: range)
        return nil
    }

    static func insert(_ text: String, into targetApp: NSRunningApplication?,
                       targetField: FocusedFieldReader.FocusSpot?, fit: Bool) async -> String? {
        // Same app, other field: never write there. Only a proven different
        // field counts; an app that doesn't tell gets the text as before.
        if let targetField, let pid = targetApp?.processIdentifier,
           let now = FocusedFieldReader.focusSpot(pid: pid, textFieldOnly: false),
           !now.isSameField(as: targetField) {
            TextInsertion.copy(text)
            NSLog("Tippi: dictation not inserted — focus moved to another field (\(now.fingerprint.role ?? "?"))")
            return String(localized: "dictation.toast.fieldChangedCopied")
        }
        // Read right before writing: that is where the text actually goes.
        let field = fit ? targetApp.flatMap { FocusedFieldReader.text(pid: $0.processIdentifier) } : nil
        let fitted = InsertionFitter.fit(text, around: field)
        logFit(fit: fit, field: field, original: text, fitted: fitted)
        await TextInsertion.replace(with: fitted, in: targetApp)
        return nil
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
