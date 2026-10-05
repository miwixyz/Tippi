import AppKit
import SwiftUI

/// AppKit-backed plain-text editor for the Notes feature.
///
/// SwiftUI's own `TextEditor(text: String)` already coerces pasted content
/// down to plain text (its backing `NSTextView` has `isRichText = false`),
/// but it exposes no hook to notice *when* that stripping actually mattered
/// — needed for the "Formatting removed" toast — and no way to turn on
/// continuous spell checking. Both require dropping to `NSViewRepresentable`.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onPasteStrippedFormatting: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.font = NotesPreferences.editorFont
        textView.usesFontPanel = true
        // Real feedback, 2026-09-13: text sat "gequetscht" (cramped) right
        // against the top/side edges at the old 8pt inset.
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.string = text
        textView.onPasteStrippedFormatting = onPasteStrippedFormatting
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        textView.drawsBackground = false

        return scrollView
    }

    /// Only pushes `text` into the view when it actually differs — otherwise
    /// every keystroke's own SwiftUI update cycle would reset the cursor
    /// position on the `NSTextView` it just typed into.
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PasteAwareTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }

    /// Overrides paste to notice — before the base implementation coerces it
    /// to plain text — whether the pasteboard held anything beyond plain
    /// text (RTF/RTFD/HTML: a styled email, a Word doc, a webpage
    /// selection). The actual stripping already happens for free via
    /// `isRichText = false`; this only adds the user-visible confirmation.
    final class PasteAwareTextView: NSTextView {
        var onPasteStrippedFormatting: (() -> Void)?

        override func paste(_ sender: Any?) {
            let richTypes: Set<NSPasteboard.PasteboardType> = [.rtf, .rtfd, .html]
            let hadRichContent = NSPasteboard.general.types?.contains(where: richTypes.contains) ?? false
            super.paste(sender)
            if hadRichContent {
                onPasteStrippedFormatting?()
            }
        }

        // MARK: Lists (2026-10-05) — logic in `NoteListEditing`, only the wiring here.
        // All edits go through `insertText(_:replacementRange:)`: that registers
        // undo (⌘Z) and fires `textDidChange`, so the binding and autosave follow.

        /// Return inside a list item continues the list; Return on an empty item
        /// ends it. Anywhere else (or while composing with an input method) the
        /// normal newline.
        override func insertNewline(_ sender: Any?) {
            let selection = selectedRange()
            guard !hasMarkedText(), selection.length == 0 else { return super.insertNewline(sender) }
            let ns = string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            guard let item = NoteListEditing.parse(line) else { return super.insertNewline(sender) }
            let prefixLength = (item.prefix as NSString).length
            // Cursor inside the marker ("- |[ ] …"): a normal newline, nothing clever.
            guard selection.location - lineRange.location >= prefixLength else { return super.insertNewline(sender) }

            switch NoteListEditing.continuation(forLineBeforeCursor: line) {
            case .none:
                super.insertNewline(sender)
            case .endList(let length):
                insertText("", replacementRange: NSRange(location: lineRange.location, length: length))
            case .continueWith(let prefix):
                insertText("\n" + prefix, replacementRange: selection)
                scrollRangeToVisible(selectedRange())
            }
        }

        /// A single click on `[ ]` / `[x]` checks or unchecks the item without
        /// moving the cursor. Every other click is a normal click.
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 1,
               event.modifierFlags.isDisjoint(with: [.shift, .command, .option, .control]),
               toggleCheckbox(at: event) {
                return
            }
            super.mouseDown(with: event)
        }

        private func toggleCheckbox(at event: NSEvent) -> Bool {
            let ns = string as NSString
            guard ns.length > 0 else { return false }
            let point = convert(event.locationInWindow, from: nil)
            let index = min(characterIndexForInsertion(at: point), ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            guard let box = NoteListEditing.checkboxRange(in: line),
                  let replacement = NoteListEditing.toggledCheckbox(in: line) else { return false }
            let boxInText = NSRange(location: lineRange.location + box.location, length: box.length)
            // Insertion index alone is too coarse (a click right of a short line
            // maps to its end) — require the pointer to be on the box itself.
            let boxOnScreen = firstRect(forCharacterRange: boxInText, actualRange: nil)
            guard boxOnScreen.insetBy(dx: -3, dy: -2).contains(NSEvent.mouseLocation) else { return false }

            let selection = selectedRange()
            insertText(replacement, replacementRange: boxInText)
            setSelectedRange(selection)   // same length — the old selection is still valid
            return true
        }

        /// Toolbar / shortcut: makes the selected lines (or the cursor's line) a
        /// list of `kind`, or plain text again when they already are one.
        func applyList(_ kind: NoteListEditing.Kind) {
            window?.makeFirstResponder(self)
            let ns = string as NSString
            let lineRange = ns.lineRange(for: selectedRange())
            var block = ns.substring(with: lineRange)
            let endsWithNewline = block.hasSuffix("\n")
            if endsWithNewline { block.removeLast() }
            let converted = NoteListEditing.toggle(kind, lines: block.components(separatedBy: "\n"))
                .joined(separator: "\n")
            insertText(converted + (endsWithNewline ? "\n" : ""), replacementRange: lineRange)
            let length = (converted as NSString).length
            // One line: cursor at its end (ready to type). Several: keep them selected.
            if block.contains("\n") {
                setSelectedRange(NSRange(location: lineRange.location, length: length))
            } else {
                setSelectedRange(NSRange(location: lineRange.location + length, length: 0))
            }
        }

        /// Called by AppKit when the user picks a font in the system Font
        /// Panel (`NSFontManager.shared.orderFrontFontPanel`, wired to the
        /// toolbar button in `NotesRootView`). With `isRichText = false`
        /// there's no per-character attribute storage to update piecemeal —
        /// setting `font` directly is the correct, and only, way to apply a
        /// uniform font to plain-text content. Persisted immediately so the
        /// next note opened (a fresh `PlainTextEditor` instance, since
        /// `NotesEditorView` is recreated per `.id(note.id)`) picks it up too.
        override func changeFont(_ sender: Any?) {
            guard let manager = sender as? NSFontManager else { return }
            let newFont = manager.convert(font ?? NotesPreferences.editorFont)
            font = newFont
            NotesPreferences.fontName = newFont.fontName
            NotesPreferences.fontSize = Double(newFont.pointSize)
        }
    }
}

extension NSView {
    /// Depth-first search for the first subview of a given type — used by
    /// the Notes font-panel button to find the note's `PasteAwareTextView`
    /// and force focus onto it before the panel opens, since `changeFont(_:)`
    /// only reaches a view via the responder chain if it's already first
    /// responder at the moment a font gets picked.
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let found = subview.firstDescendant(ofType: type) { return found }
        }
        return nil
    }
}
