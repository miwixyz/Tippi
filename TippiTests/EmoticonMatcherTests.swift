import XCTest
@testable import Tippi

/// Emoticons are the loosest of the three expansion patterns — no closing
/// delimiter, and the shortest ones (`:(`, `:/`) appear verbatim inside code
/// and URLs. The negative tests are the point of this file.
final class EmoticonMatcherTests: XCTestCase {

    // MARK: - Positive cases

    func testMatchesAfterSpace() {
        XCTAssertEqual(EmoticonMatcher.match(in: "Hallo :-)")?.emoji, "🙂")
        XCTAssertEqual(EmoticonMatcher.match(in: "Schade :(")?.emoji, "🙁")
        XCTAssertEqual(EmoticonMatcher.match(in: "Ich <3")?.emoji, "❤️")
        XCTAssertEqual(EmoticonMatcher.match(in: "haha XD")?.emoji, "😆")
    }

    func testMatchesAtStartOfBuffer() {
        // The buffer resets on Return/Tab/arrows and app switches, so an empty
        // prefix genuinely means "start of what's being typed".
        XCTAssertEqual(EmoticonMatcher.match(in: ":-)")?.emoji, "🙂")
        XCTAssertEqual(EmoticonMatcher.match(in: "<3")?.emoji, "❤️")
    }

    func testMatchesAfterNewlineAndTab() {
        XCTAssertEqual(EmoticonMatcher.match(in: "line\n:-)")?.emoji, "🙂")
        XCTAssertEqual(EmoticonMatcher.match(in: "col\t;-)")?.emoji, "😉")
    }

    func testTriggerLengthMatchesEmoticonLength() {
        XCTAssertEqual(EmoticonMatcher.match(in: "a :-)")?.triggerLength, 3)
        XCTAssertEqual(EmoticonMatcher.match(in: "a :(")?.triggerLength, 2)
        XCTAssertEqual(EmoticonMatcher.match(in: "a </3")?.triggerLength, 3)
    }

    /// `>:(` ends with `:(`. Scanning shortest-first would downgrade an angry
    /// face to a sad one.
    func testLongestMatchWinsOverShorterSuffix() {
        XCTAssertEqual(EmoticonMatcher.match(in: "grr >:(")?.emoji, "😠")
        XCTAssertEqual(EmoticonMatcher.match(in: "aua </3")?.emoji, "💔")
    }

    func testBothWinkVariants() {
        XCTAssertEqual(EmoticonMatcher.match(in: "ok ;)")?.emoji, "😉")
        XCTAssertEqual(EmoticonMatcher.match(in: "ok ;-)")?.emoji, "😉")
    }

    // MARK: - Letter-ending emoticons need a trailing boundary (2026-09-13)

    /// The reported bug: typing `:ot` converted `:o` to 😮 the instant "o"
    /// completed it, leaving "😮t" once "t" landed. `:o` is a real word
    /// prefix (open, other, only, …) — it must never fire until something
    /// that clearly isn't a word continuation follows.
    func testAmbiguousLetterEmoticonDoesNotFireMidWord() {
        XCTAssertNil(EmoticonMatcher.match(in: "sag :o"))     // "o" just typed, could still be a word
        XCTAssertNil(EmoticonMatcher.match(in: "sag :ot"))    // confirmed: it was a word
        XCTAssertNil(EmoticonMatcher.match(in: "sag :ot"), "must stay nil however long the word gets")
    }

    func testAmbiguousLetterEmoticonFiresOnceConfirmedByBoundary() {
        let match = EmoticonMatcher.match(in: "sag :o ")
        XCTAssertEqual(match?.emoji, "😮")
        XCTAssertEqual(match?.replacement, "😮 ", "the confirming space must be re-inserted, not swallowed")
        XCTAssertEqual(match?.triggerLength, 3, "\":o\" (2) + the confirming space (1)")
    }

    func testAmbiguousLetterEmoticonFiresOnPunctuationBoundaryToo() {
        XCTAssertEqual(EmoticonMatcher.match(in: "wow :p!")?.replacement, "😛!")
        XCTAssertEqual(EmoticonMatcher.match(in: "wow :-O.")?.replacement, "😮.")
    }

    /// Bare letter combos with no colon/semicolon prefix aren't ambiguous the
    /// same way — nothing accidentally starts a word with "XD" — so they must
    /// keep firing immediately, same as before this fix.
    func testBareLetterEmoticonStillFiresImmediately() {
        XCTAssertEqual(EmoticonMatcher.match(in: "haha XD")?.emoji, "😆")
        XCTAssertEqual(EmoticonMatcher.match(in: "haha XD")?.replacement, "😆")
    }

    // MARK: - Must NOT match (the whole reason the boundary rule exists)

    func testDoesNotFireInsidePythonSlicing() {
        XCTAssertNil(EmoticonMatcher.match(in: "x = a[:("))
        XCTAssertNil(EmoticonMatcher.match(in: "d[:("))
    }

    func testDoesNotFireInsideFormatString() {
        XCTAssertNil(EmoticonMatcher.match(in: "printf(\"%s:("))
    }

    func testDoesNotFireInsideURL() {
        XCTAssertNil(EmoticonMatcher.match(in: "http:/"))
        XCTAssertNil(EmoticonMatcher.match(in: "https:/"))
    }

    func testDoesNotFireMidWord() {
        XCTAssertNil(EmoticonMatcher.match(in: "maxD"))
        XCTAssertNil(EmoticonMatcher.match(in: "foo:("))
    }

    /// A known emoticon that fails the boundary check must abort the scan
    /// rather than fall through to a shorter one that would match further
    /// right — otherwise `a>:(` would still insert 🙁 via the trailing `:(`.
    func testFailedBoundaryDoesNotFallThroughToShorterEmoticon() {
        XCTAssertNil(EmoticonMatcher.match(in: "a>:("))
        XCTAssertNil(EmoticonMatcher.match(in: "x</3"))
    }

    func testUnknownEmoticonDoesNotMatch() {
        XCTAssertNil(EmoticonMatcher.match(in: "what :-Z"))
        XCTAssertNil(EmoticonMatcher.match(in: "hmm ¯\\_(ツ)_/¯"))
    }

    func testEmptyBuffer() {
        XCTAssertNil(EmoticonMatcher.match(in: ""))
    }

    // MARK: - Table sanity

    func testEveryMappedValueIsNonEmptyAndNotTheEmoticonItself() {
        for (emoticon, emoji) in EmoticonMatcher.map {
            XCTAssertFalse(emoji.isEmpty, "\(emoticon) maps to an empty string")
            XCTAssertNotEqual(emoticon, emoji, "\(emoticon) maps to itself")
        }
    }

    /// Expanding to something that is itself a trigger would loop: the
    /// injected text must never be re-matchable as another emoticon.
    func testNoMappedEmojiIsItselfAnEmoticonTrigger() {
        for (_, emoji) in EmoticonMatcher.map {
            XCTAssertNil(EmoticonMatcher.match(in: " \(emoji)"),
                         "inserting \(emoji) would immediately re-trigger")
        }
    }
}
