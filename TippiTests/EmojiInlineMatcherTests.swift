import XCTest
@testable import Tippi

/// The matcher runs on every keystroke the user types *anywhere* on the Mac,
/// so the tests that matter most are the negative ones: what it must refuse
/// to touch. A false positive here silently eats characters out of unrelated
/// text — worse than the feature simply not firing.
final class EmojiInlineMatcherTests: XCTestCase {

    // MARK: - Positive cases

    func testMatchesSimpleName() {
        let match = EmojiInlineMatcher.candidate(in: "Danke :rakete:")
        XCTAssertEqual(match?.alias, "rakete")
    }

    func testTriggerLengthCoversBothColons() {
        let match = EmojiInlineMatcher.candidate(in: ":ok:")
        // ":ok:" is 4 characters — deleting fewer would leave a stray colon.
        XCTAssertEqual(match?.triggerLength, 4)
    }

    func testMatchesNameWithUnderscoreAndDigits() {
        XCTAssertEqual(EmojiInlineMatcher.candidate(in: "x :daumen_hoch:")?.alias, "daumen_hoch")
        XCTAssertEqual(EmojiInlineMatcher.candidate(in: ":u7121:")?.alias, "u7121")
    }

    func testMatchesNameWithHyphen() {
        XCTAssertEqual(EmojiInlineMatcher.candidate(in: ":e-mail:")?.alias, "e-mail")
    }

    /// GitHub-style `:+1:` is deliberately NOT supported: requiring at least
    /// one letter is what stops a score line like "10:1:" from turning into
    /// 👍 (CLDR really does list "1" as a keyword for thumbs-up). Verified
    /// against the shipped database — no emoji has a letterless name, so this
    /// rule costs zero reachability. 👍 stays available as :daumen:,
    /// :daumen_hoch:, :thumbs_up:, :like: and :ok:.
    func testRejectsLetterlessNamesSoScoreLinesAreSafe() {
        XCTAssertNil(EmojiInlineMatcher.candidate(in: ":+1:"))
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "Endstand 10:1:"))
    }

    func testUsesInnermostColonPair() {
        // "12:30 :rakete:" — the opening colon of the emoji is the last one
        // before the closing colon, not the one in the timestamp.
        let match = EmojiInlineMatcher.candidate(in: "Termin 12:30 :rakete:")
        XCTAssertEqual(match?.alias, "rakete")
    }

    // MARK: - Must NOT match

    func testRejectsPureDigitsSoTimestampsAreSafe() {
        // Typing "12:30:" while writing a time range must never trigger.
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "12:30:"))
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "von 9:00:"))
    }

    func testRejectsSpacesSoProseIsSafe() {
        // "Notiz: das:" — a colon, prose, another colon. Must stay untouched.
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "Notiz: das:"))
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "Achtung: hier:"))
    }

    func testRejectsUrlPatterns() {
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "https://example.com:"))
    }

    func testRejectsEmptyAndTooShortNames() {
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "::"))
        XCTAssertNil(EmojiInlineMatcher.candidate(in: ":a:"))
    }

    func testRejectsOverlongNames() {
        let long = String(repeating: "a", count: EmojiInlineMatcher.maxNameLength + 1)
        XCTAssertNil(EmojiInlineMatcher.candidate(in: ":\(long):"))
    }

    func testRejectsWithoutClosingColon() {
        XCTAssertNil(EmojiInlineMatcher.candidate(in: ":rakete"))
    }

    func testRejectsWithoutOpeningColon() {
        XCTAssertNil(EmojiInlineMatcher.candidate(in: "rakete:"))
    }

    func testRejectsPunctuationInsideName() {
        XCTAssertNil(EmojiInlineMatcher.candidate(in: ":rake.te:"))
        XCTAssertNil(EmojiInlineMatcher.candidate(in: ":rake/te:"))
    }

    func testAcceptsAtBoundaryLengths() {
        let min = String(repeating: "a", count: EmojiInlineMatcher.minNameLength)
        let max = String(repeating: "a", count: EmojiInlineMatcher.maxNameLength)
        XCTAssertEqual(EmojiInlineMatcher.candidate(in: ":\(min):")?.alias, min)
        XCTAssertEqual(EmojiInlineMatcher.candidate(in: ":\(max):")?.alias, max)
    }
}
