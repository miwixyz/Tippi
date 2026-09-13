import Foundation

/// Converts classic text emoticons into emoji while typing: `:-)` → 🙂.
///
/// Harder to get right than `:name:` shortcodes, because an emoticon has no
/// closing delimiter announcing "I'm done". `:(` is complete the moment it's
/// typed — but it is also a real substring of Python slicing (`a[:(b)]`), C
/// format strings (`"%s:(%d)"`), and `://` in every URL. Two rules keep it out
/// of that territory:
///
/// 1. **Word boundary.** The character before the emoticon must be whitespace
///    or the very start of the buffer. That single rule kills every realistic
///    false positive: `a[:(` has `[` in front, `printf("%s:(` has `s`,
///    `http:/` has `p`. Verified against those exact cases in the tests.
/// 2. **Longest match first.** `>:(` ends with `:(`, so scanning shortest-first
///    would turn an angry face into a merely sad one.
///
/// The whole feature is a single toggle (`EmojiSettings.isEmoticonEnabled`).
/// Off by default it is not — but switching it off leaves `:name:` shortcodes
/// and the picker fully intact, since they're independent paths.
enum EmoticonMatcher {

    /// Deliberately conservative. Every entry is an emoticon people actually
    /// type in chat; obscure kaomoji are left out because each addition is
    /// another chance to fire on something that wasn't an emoticon at all.
    static let map: [String: String] = [
        // Smiling
        ":-)": "🙂", ":)": "🙂", "(-:": "🙂",
        ":-D": "😃", ":D": "😃",
        "^_^": "😊",
        // Winking / playful
        ";-)": "😉", ";)": "😉",
        ":-P": "😛", ":P": "😛", ":-p": "😛", ":p": "😛",
        "XD": "😆", "xD": "😆",
        // Sad / upset
        ":-(": "🙁", ":(": "🙁", ")-:": "🙁",
        ":'(": "😢", "T_T": "😭",
        ">:(": "😠", ">:-(": "😠",
        // Neutral / unsure
        ":-|": "😐", ":|": "😐",
        ":-/": "😕", ":/": "😕", ":-\\": "😕",
        // Surprise
        ":-O": "😮", ":O": "😮", ":-o": "😮", ":o": "😮",
        // Other classics
        "8-)": "😎",
        ":-*": "😘",
        "<3": "❤️", "</3": "💔",
        "\\o/": "🙌",
    ]

    /// Longest first, so `>:(` wins over `:(`. Computed once — this is read on
    /// every keystroke and re-sorting 30 strings each time would be waste.
    private static let byLengthDescending: [(emoticon: String, emoji: String)] =
        map.sorted { $0.key.count > $1.key.count }
           .map { (emoticon: $0.key, emoji: $0.value) }

    struct Match: Equatable {
        let emoticon: String
        let emoji: String
        /// Set only for emoticons that end in a letter (`:o`, `:O`, `:p`,
        /// `:P`, incl. their `:-` variants) — see `match(in:)`. The character
        /// that confirmed the match (a space or punctuation typed right
        /// after) must be re-inserted, since it belongs to the user's text,
        /// not to the emoticon.
        let trailingBoundary: Character?

        /// Characters to delete before inserting the emoji.
        var triggerLength: Int { emoticon.count + (trailingBoundary != nil ? 1 : 0) }
        /// What actually gets typed back — the emoji, plus the trailing
        /// boundary character if one had to be consumed to confirm the match.
        var replacement: String { trailingBoundary.map { emoji + String($0) } ?? emoji }
    }

    /// `:o`, `:O`, `:p`, `:P` and their `:-` variants — a colon/semicolon
    /// directly followed by exactly one letter — are also the literal start
    /// of every real word beginning with that letter. `:ot` reported
    /// 2026-09-13: the instant `:o` completed, it converted to 😮, leaving
    /// "😮t" once the rest of the word was typed. Deliberately narrow: bare
    /// letter combos with no colon prefix (`XD`, `xD`) are not ambiguous the
    /// same way — nobody accidentally starts an unrelated word with "XD" —
    /// so they keep firing immediately, and `testMatchesAfterSpace` (which
    /// expects exactly that for "haha XD") stays green.
    private static func needsTrailingBoundary(_ emoticon: String) -> Bool {
        guard let first = emoticon.first, first == ":" || first == ";" else { return false }
        var rest = emoticon.dropFirst()
        if rest.first == "-" { rest = rest.dropFirst() }
        return rest.count == 1 && (rest.first?.isLetter ?? false)
    }

    /// Returns a match if `buffer` ends with a known emoticon that starts at a
    /// word boundary. Nil otherwise — the typed text is then left untouched.
    static func match(in buffer: String) -> Match? {
        for candidate in byLengthDescending {
            // Punctuation-ending emoticons (`:)`, `:(`, `<3`, `XD`, …) don't
            // have the word-prefix problem — no English word continues with
            // `)`/`(`/`3` mid-token, and bare letter combos like `XD` have no
            // colon prefix to collide with — so only the handful matching
            // `needsTrailingBoundary` wait for one more, non-word character
            // before firing. Same "confirm with a boundary char" idiom the
            // Space-accepts-suggestion path elsewhere already uses.
            let needsBoundary = needsTrailingBoundary(candidate.emoticon)
            let core: Substring
            var trailingBoundary: Character?
            if needsBoundary {
                guard let last = buffer.last, !last.isLetter, !last.isNumber else { continue }
                let withoutBoundary = buffer.dropLast()
                guard withoutBoundary.hasSuffix(candidate.emoticon) else { continue }
                core = withoutBoundary
                trailingBoundary = last
            } else {
                guard buffer.hasSuffix(candidate.emoticon) else { continue }
                core = buffer[...]
            }

            let preceding = core.dropLast(candidate.emoticon.count)
            // Start of buffer counts as a boundary: the buffer is reset on
            // Return/Tab/Escape/arrow keys and on app switches, so "empty" here
            // genuinely means "start of what the user is typing", not
            // "somewhere in the middle of a word we've forgotten about".
            guard let previous = preceding.last else {
                return Match(emoticon: candidate.emoticon, emoji: candidate.emoji, trailingBoundary: trailingBoundary)
            }
            if previous.isWhitespace {
                return Match(emoticon: candidate.emoticon, emoji: candidate.emoji, trailingBoundary: trailingBoundary)
            }
            // A known emoticon that failed the boundary check must stop the
            // scan rather than fall through to a shorter one: `a[:(` should
            // insert nothing at all, not match the shorter `:(` further right.
            return nil
        }
        return nil
    }
}
