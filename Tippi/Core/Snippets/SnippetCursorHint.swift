import Foundation

/// Espanso's cursor hint: `$|$` marks where the caret should end up after a
/// snippet expands.
///
/// Tippi reads Espanso's match files directly, so a snippet written for Espanso
/// carries this marker — and until now it was inserted literally, leaving `$|$`
/// sitting in the user's text (reported 2026-09-10 for `:verl`).
///
/// Pure string logic on purpose: the caret move itself is synthetic keystrokes,
/// which cannot be unit-tested, but deciding *how far* to move can be.
enum SnippetCursorHint {
    static let marker = "$|$"

    /// Splits the expansion into the text to insert and how many characters the
    /// caret must move back afterwards.
    ///
    /// Only the first marker is honoured — that is Espanso's behaviour, and a
    /// second one has no meaningful interpretation. Any further markers are left
    /// in the text rather than silently removed, so the user can see that
    /// something in their snippet is off.
    static func split(_ raw: String) -> (text: String, caretOffsetFromEnd: Int) {
        guard let range = raw.range(of: marker) else { return (raw, 0) }
        let before = String(raw[raw.startIndex..<range.lowerBound])
        let after = String(raw[range.upperBound...])
        // The offset counts characters, not bytes: the caret moves in arrow-key
        // steps, and an emoji or umlaut after the marker is one step, not two.
        return (before + after, after.count)
    }
}
