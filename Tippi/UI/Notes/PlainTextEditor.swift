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
