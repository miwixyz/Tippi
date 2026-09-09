import XCTest
@testable import Tippi

final class LocalTextTransformerTests: XCTestCase {
    func testTransliteratesAllGermanUmlautsAndEszett() {
        let input = "Grüße äöü ÄÖÜ groß Straße"
        let result = LocalTextTransformer.transliterateUmlauts(input)
        XCTAssertEqual(result, "Gruesse aeoeue AeOeUe gross Strasse")
    }

    func testTransliterationPreservesTextWithoutUmlauts() {
        XCTAssertEqual(LocalTextTransformer.transliterateUmlauts("Hello World"), "Hello World")
    }

    /// The real-world trigger for this feature: "Underscore" on a filename
    /// candidate must be genuinely web-safe, not just word-joined with raw
    /// umlauts still inside it.
    func testUnderscoreTransliteratesUmlautsBeforeJoining() {
        XCTAssertEqual(LocalTextTransformer.underscore("Über uns"), "Ueber_uns")
    }

    func testHyphenateTransliteratesUmlautsBeforeJoining() {
        XCTAssertEqual(LocalTextTransformer.hyphenate("Straße gesperrt"), "Strasse-gesperrt")
    }

    /// Non-German accented characters (French é, etc.) are intentionally out
    /// of scope — this maps the German umlaut/eszett set only, matching the
    /// vault's own file-naming convention, not a general accent-stripper.
    func testNonGermanAccentsAreLeftUntouched() {
        XCTAssertEqual(LocalTextTransformer.transliterateUmlauts("Café"), "Café")
    }

    /// Regression test for a real bug (2026-09-09): `.uppercase` and
    /// `.lowercase` both used the SF Symbol "textformat" — invisible in the
    /// full popup (which shows a text title next to each icon), but the two
    /// actions became visually indistinguishable the moment an icon-only
    /// context (the selection action bar) started reusing this same list.
    /// Every action needs a symbol no other action uses.
    func testEveryLocalActionHasAUniqueSymbol() {
        let symbols = LocalTextAction.all.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "duplicate icon(s) found: \(symbols)")
    }
}
