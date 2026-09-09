import XCTest
@testable import Tippi

/// Ranking and normalization only — no bundle, no database load, so these run
/// fast and deterministically. The fixtures mirror the real CLDR shape.
final class EmojiSearchTests: XCTestCase {

    private let rocket = Emoji(
        character: "🚀", nameDE: "rakete", nameEN: "rocket",
        keywords: ["weltraum", "space", "launch"]
    )
    private let popcorn = Emoji(
        character: "🍿", nameDE: "popcorn", nameEN: "popcorn",
        keywords: ["kino", "snack", "movie"]
    )
    private let clapper = Emoji(
        character: "🎬", nameDE: "filmklappe", nameEN: "clapper_board",
        keywords: ["film", "klappe", "action"]
    )

    private var fixtures: [Emoji] { [rocket, popcorn, clapper] }

    // MARK: - Normalization

    func testNormalizeTransliteratesUmlauts() {
        XCTAssertEqual(EmojiSearch.normalize("grün"), "gruen")
        XCTAssertEqual(EmojiSearch.normalize("Öl"), "oel")
        XCTAssertEqual(EmojiSearch.normalize("Straße"), "strasse")
    }

    func testNormalizeLowercasesAndStripsPunctuation() {
        XCTAssertEqual(EmojiSearch.normalize("Rakete!"), "rakete")
        XCTAssertEqual(EmojiSearch.normalize("  Daumen hoch  "), "daumen_hoch")
    }

    func testNormalizeCollapsesSeparators() {
        XCTAssertEqual(EmojiSearch.normalize("daumen   hoch"), "daumen_hoch")
        XCTAssertEqual(EmojiSearch.normalize("e-mail"), "e_mail")
    }

    /// Guards the one silent-breakage risk in this feature: the generator
    /// writes slugs with its own Python transliteration. If the two ever drift,
    /// umlaut searches quietly return nothing instead of failing loudly.
    func testNormalizeMatchesGeneratorSlugRules() {
        XCTAssertEqual(EmojiSearch.normalize("Gesicht mit Freudentränen"),
                       "gesicht_mit_freudentraenen")
        XCTAssertEqual(EmojiSearch.normalize("Flagge: Deutschland"),
                       "flagge_deutschland")
    }

    // MARK: - Ranking

    func testExactNameBeatsKeyword() {
        // "popcorn" is 🍿's name; nothing else should outrank it.
        let results = EmojiSearch.rank(fixtures, query: "popcorn", limit: 10)
        XCTAssertEqual(results.first?.character, "🍿")
    }

    func testGermanAndEnglishNamesBothMatch() {
        XCTAssertEqual(EmojiSearch.rank(fixtures, query: "rakete", limit: 5).first?.character, "🚀")
        XCTAssertEqual(EmojiSearch.rank(fixtures, query: "rocket", limit: 5).first?.character, "🚀")
    }

    func testKeywordMatchesWhenNoNameMatches() {
        // "kino" is only a keyword of 🍿 — the real-world case that made
        // German keywords worth shipping.
        let results = EmojiSearch.rank(fixtures, query: "kino", limit: 5)
        XCTAssertEqual(results.first?.character, "🍿")
    }

    func testPrefixMatchRanksAboveSubstringMatch() {
        // "film" is a prefix of "filmklappe" (name) and also a keyword of 🎬.
        let results = EmojiSearch.rank(fixtures, query: "film", limit: 5)
        XCTAssertEqual(results.first?.character, "🎬")
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(EmojiSearch.rank(fixtures, query: "zzzznotanemoji", limit: 5).isEmpty)
    }

    func testLimitIsRespected() {
        // "o" appears in every fixture's name or keywords.
        XCTAssertEqual(EmojiSearch.rank(fixtures, query: "o", limit: 2).count, 2)
    }

    func testRankingIsStableAcrossCalls() {
        let first = EmojiSearch.rank(fixtures, query: "o", limit: 10).map(\.character)
        let second = EmojiSearch.rank(fixtures, query: "o", limit: 10).map(\.character)
        XCTAssertEqual(first, second)
    }
}
