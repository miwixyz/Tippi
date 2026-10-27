import AppKit

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
        await TextInsertion.replace(with: InsertionFitter.fit(text, around: field), in: targetApp)
        return nil
    }
}
