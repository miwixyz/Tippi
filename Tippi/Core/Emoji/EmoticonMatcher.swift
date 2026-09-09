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
        /// Characters to delete before inserting the emoji.
        var triggerLength: Int { emoticon.count }
    }

    /// Returns a match if `buffer` ends with a known emoticon that starts at a
    /// word boundary. Nil otherwise — the typed text is then left untouched.
    static func match(in buffer: String) -> Match? {
        for candidate in byLengthDescending where buffer.hasSuffix(candidate.emoticon) {
            let preceding = buffer.dropLast(candidate.emoticon.count)
            // Start of buffer counts as a boundary: the buffer is reset on
            // Return/Tab/Escape/arrow keys and on app switches, so "empty" here
            // genuinely means "start of what the user is typing", not
            // "somewhere in the middle of a word we've forgotten about".
            guard let previous = preceding.last else {
                return Match(emoticon: candidate.emoticon, emoji: candidate.emoji)
            }
            if previous.isWhitespace {
                return Match(emoticon: candidate.emoticon, emoji: candidate.emoji)
            }
            // A known emoticon that failed the boundary check must stop the
            // scan rather than fall through to a shorter one: `a[:(` should
            // insert nothing at all, not match the shorter `:(` further right.
            return nil
        }
        return nil
    }
}
