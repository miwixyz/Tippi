import XCTest
@testable import Tippi

/// `openPrefix` decides when a suggestion popup appears over whatever the user
/// is writing. It runs on every keystroke system-wide, so the negative cases
/// matter more than the positive ones: a list popping up while someone types a
/// URL or a Python slice is worse than no list at all.
final class EmojiOpenPrefixTests: XCTestCase {

    // MARK: - Should open

    func testOpensOnSingleLetterAfterSpace() {
        // Michael's case: ":e" should already suggest something.
        XCTAssertEqual(EmojiInlineMatcher.openPrefix(in: "Danke :e"), "e")
    }

    func testOpensAtStartOfBuffer() {
        XCTAssertEqual(EmojiInlineMatcher.openPrefix(in: ":lach"), "lach")
    }

    func testOpensAfterNewline() {
        XCTAssertEqual(EmojiInlineMatcher.openPrefix(in: "Zeile\n:rak"), "rak")
    }

    func testAllowsDigitsUnderscoreAndHyphen() {
        XCTAssertEqual(EmojiInlineMatcher.openPrefix(in: " :daumen_ho"), "daumen_ho")
        XCTAssertEqual(EmojiInlineMatcher.openPrefix(in: " :e-ma"), "e-ma")
        XCTAssertEqual(EmojiInlineMatcher.openPrefix(in: " :u71"), "u71")
    }

    // MARK: - Should NOT open

    /// The closing colon means the `:name:` path already handled it — showing
    /// a list at that moment would flash for one frame and vanish.
    func testDoesNotOpenOnceClosingColonTyped() {
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: ":lach:"))
    }

    func testDoesNotOpenInsideURL() {
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "https:"))
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "http:/"))
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "https://exa"))
    }

    func testDoesNotOpenInCodeContexts() {
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "a[:b"))
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "dict = {\"key\":val"))
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "Hinweis:wichtig"))
    }

    func testDoesNotOpenWithoutColon() {
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "einfach text"))
    }

    func testDoesNotOpenOnEmptyPrefix() {
        // A bare colon is not yet an intent to pick an emoji.
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "Uhrzeit :"))
    }

    func testDoesNotOpenOnSpaceAfterPrefix() {
        // Space is the accept key; by the time it lands the prefix is finished
        // and this must no longer report an open prefix.
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: ":lach "))
    }

    func testDoesNotOpenBeyondMaxLength() {
        let long = String(repeating: "a", count: EmojiInlineMatcher.maxNameLength + 1)
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: " :\(long)"))
    }

    func testDoesNotOpenOnTimestamp() {
        XCTAssertNil(EmojiInlineMatcher.openPrefix(in: "12:30"))
    }

    // MARK: - Interaction with the accept path

    /// Space-accept computes its backspace count from the prefix measured on
    /// the buffer minus the space. Off-by-one here would eat a character of
    /// the user's actual text.
    func testPrefixLengthDrivesCorrectDeletionCount() {
        let buffer = "Danke :lach "
        let prefix = EmojiInlineMatcher.openPrefix(in: String(buffer.dropLast()))
        XCTAssertEqual(prefix, "lach")
        // ":" + "lach" + " " = 6 characters to retract.
        XCTAssertEqual((prefix?.count ?? 0) + 2, 6)
        XCTAssertTrue(buffer.hasSuffix(":lach "))
    }
}
