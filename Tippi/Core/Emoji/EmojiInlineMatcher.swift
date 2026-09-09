import Foundation

/// Detects a completed `:name:` sequence at the end of the typed buffer.
///
/// Pure logic, no AppKit — the interesting part is what it *refuses* to match.
/// This runs on every keystroke the user types anywhere on the Mac, so a
/// sloppy rule here would eat characters out of unrelated text. The guards:
///
/// - the name must contain at least one letter, so timestamps (`12:30:`) and
///   numeric ranges never trigger
/// - only `a–z 0–9 _ + -` are allowed inside, so `Notiz: das:` (space) and
///   `http://` are out
/// - length 2…40, so a lone `::` does nothing and a runaway buffer can't
///   produce an absurd backspace count
/// - the name must resolve to a real emoji; unknown names leave the text
///   exactly as typed rather than deleting it
enum EmojiInlineMatcher {
    static let minNameLength = 2
    static let maxNameLength = 40

    struct Match: Equatable {
        /// The alias between the colons, e.g. "rakete".
        let alias: String
        /// Characters to delete before inserting — `:rakete:` = 8.
        var triggerLength: Int { alias.count + 2 }
    }

    /// Returns the candidate name if the buffer ends in a well-formed
    /// `:name:`. Whether that name actually exists is the caller's lookup —
    /// keeping the two apart is what makes this testable without a database.
    static func candidate(in buffer: String) -> Match? {
        guard buffer.hasSuffix(":") else { return nil }

        // Walk backwards from the closing colon to the opening one.
        let withoutClosing = buffer.dropLast()
        guard let openIndex = withoutClosing.lastIndex(of: ":") else { return nil }

        let name = withoutClosing[withoutClosing.index(after: openIndex)...]
        guard name.count >= minNameLength, name.count <= maxNameLength else { return nil }

        var hasLetter = false
        for char in name {
            if char.isLetter {
                hasLetter = true
            } else if char.isNumber || char == "_" || char == "+" || char == "-" {
                continue
            } else {
                return nil
            }
        }
        guard hasLetter else { return nil }

        return Match(alias: String(name))
    }
}
