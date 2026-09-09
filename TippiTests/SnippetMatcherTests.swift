import XCTest
@testable import Tippi

final class SnippetMatcherTests: XCTestCase {
    func testMatchesExactTrigger() {
        var matcher = SnippetMatcher()
        for char in ":nl" { matcher.appendCharacter(char) }
        XCTAssertEqual(matcher.matchedTrigger(among: [":nl", ":do"]), ":nl")
    }

    func testNoMatchBeforeTriggerComplete() {
        var matcher = SnippetMatcher()
        for char in ":n" { matcher.appendCharacter(char) }
        XCTAssertNil(matcher.matchedTrigger(among: [":nl", ":do"]))
    }

    func testLongestTriggerWinsOverShorterSuffix() {
        // ":nl-do" is typed in full; both ":nl-do" and a hypothetical shorter
        // trigger that happens to be a suffix of it must resolve to the
        // longest (most specific) one.
        var matcher = SnippetMatcher()
        for char in ":nl-do" { matcher.appendCharacter(char) }
        XCTAssertEqual(matcher.matchedTrigger(among: [":nl-do", "-do"]), ":nl-do")
    }

    func testBackspaceRemovesLastCharacter() {
        var matcher = SnippetMatcher()
        for char in ":nlx" { matcher.appendCharacter(char) }
        matcher.deleteLastCharacter()
        XCTAssertEqual(matcher.matchedTrigger(among: [":nl"]), ":nl")
    }

    func testResetClearsBuffer() {
        var matcher = SnippetMatcher()
        for char in ":nl" { matcher.appendCharacter(char) }
        matcher.reset()
        XCTAssertNil(matcher.matchedTrigger(among: [":nl"]))
    }

    func testBufferIsCappedAtMaxLength() {
        var matcher = SnippetMatcher()
        let longInput = String(repeating: "a", count: SnippetMatcher.maxBufferLength + 20)
        for char in longInput { matcher.appendCharacter(char) }
        XCTAssertEqual(matcher.buffer.count, SnippetMatcher.maxBufferLength)
    }

    func testEmptyBufferNeverMatches() {
        let matcher = SnippetMatcher()
        XCTAssertNil(matcher.matchedTrigger(among: [":nl", ""]))
    }
}
