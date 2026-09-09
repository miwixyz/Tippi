import Foundation

/// Pure trigger-matching logic — no AppKit/CGEvent here, fully unit-testable
/// without a real keyboard monitor. Mirrors Espanso's default matching
/// behaviour: a trigger matches as soon as the typed buffer *ends with* it,
/// with no word-boundary requirement (none of the real match files use
/// Espanso's `word: true` option, so that mode isn't implemented).
struct SnippetMatcher {
    /// Generous headroom above any real trigger's length (longest today is
    /// 8 characters). Caps memory and per-keystroke comparison cost.
    static let maxBufferLength = 64

    private(set) var buffer: String = ""

    mutating func reset() {
        buffer = ""
    }

    mutating func appendCharacter(_ char: Character) {
        buffer.append(char)
        if buffer.count > Self.maxBufferLength {
            buffer.removeFirst(buffer.count - Self.maxBufferLength)
        }
    }

    mutating func deleteLastCharacter() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
    }

    /// Longest-trigger-wins: checked longest-first so a more specific
    /// trigger (":nl-do") matches before a shorter one (":nl") that happens
    /// to also be a suffix of it once ":nl-do" has been fully typed... wait,
    /// ":nl" is not a suffix of ":nl-do", but ":nl-do" contains ":nl" as a
    /// prefix, not a suffix — the longest-first order still matters whenever
    /// two configured triggers share a suffix (e.g. two different user
    /// snippets both ending "...ok"), so it stays the general rule.
    func matchedTrigger(among triggers: [String]) -> String? {
        guard !buffer.isEmpty else { return nil }
        for trigger in triggers.sorted(by: { $0.count > $1.count }) where !trigger.isEmpty {
            if buffer.hasSuffix(trigger) {
                return trigger
            }
        }
        return nil
    }
}
