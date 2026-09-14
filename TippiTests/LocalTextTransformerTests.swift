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
    // MARK: - splitUnderscore (inverse of `underscore`)

    func testSplitUnderscoreSeparatesWords() {
        XCTAssertEqual(LocalTextTransformer.splitUnderscore("hallo_welt"), "hallo welt")
    }

    /// Runs of underscores must not leave runs of spaces behind.
    func testSplitUnderscoreCollapsesRepeatedUnderscores() {
        XCTAssertEqual(LocalTextTransformer.splitUnderscore("a__b"), "a b")
    }

    /// Only underscores are touched. Dots, hyphens and camel case survive —
    /// the action is "split underscores", not "slugify in reverse".
    func testSplitUnderscoreLeavesOtherSeparatorsAlone() {
        XCTAssertEqual(
            LocalTextTransformer.splitUnderscore("snake_case.and-dots"),
            "snake case.and-dots")
    }

    /// A multi-line selection keeps its line structure.
    func testSplitUnderscorePreservesLineBreaks() {
        XCTAssertEqual(
            LocalTextTransformer.splitUnderscore("erste_zeile\nzweite_zeile"),
            "erste zeile\nzweite zeile")
    }

    func testSplitUnderscoreLeavesTextWithoutUnderscoresUnchanged() {
        XCTAssertEqual(LocalTextTransformer.splitUnderscore("nichts zu tun"), "nichts zu tun")
    }

    /// Round trip through both actions. `underscore` also transliterates
    /// umlauts, so the result is the ASCII form — not the original string.
    func testUnderscoreThenSplitReturnsSpacedAsciiForm() {
        let joined = LocalTextTransformer.underscore("Über uns")
        XCTAssertEqual(LocalTextTransformer.splitUnderscore(joined), "Ueber uns")
    }

    func testEveryLocalActionHasAUniqueGlyph() {
        let glyphs = LocalTextAction.all.map { $0.label ?? $0.symbol }
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "duplicate button glyph(s): \(glyphs)")
    }

    /// The test this file was missing. Uniqueness was checked, existence was
    /// not — so `underscore`, which is not an SF Symbol at all, shipped as an
    /// invisible button and was only noticed when a user clicked the one next
    /// to it by mistake (2026-09-14).
    func testEverySymbolNameActuallyExists() {
        for action in LocalTextAction.all where action.label == nil {
            XCTAssertNotNil(
                NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil),
                "SF Symbol '\(action.symbol)' for action '\(action.kind.rawValue)' does not exist")
        }
    }

    /// Every action renders as either a label or a symbol — never as nothing.
    func testEveryActionHasSomethingToRender() {
        for action in LocalTextAction.all {
            XCTAssertFalse(
                (action.label ?? action.symbol).isEmpty,
                "action '\(action.kind.rawValue)' would render as an empty button")
        }
    }

    // MARK: - Identity cases
    //
    // These are the inputs where a transform legitimately returns its input
    // unchanged. Each one used to produce a duplicated selection: writing
    // identical text left the document unchanged, the no-op detector read that
    // as "the app ignored the write", and the clipboard fallback appended a
    // second copy. `performSelectionAction` now refuses to write when the
    // result equals the input — these tests pin down when that happens.

    func testTransliterateLeavesTextWithoutUmlautsUnchanged() {
        let input = "Wichtig ist nur"
        XCTAssertEqual(LocalTextTransformer.transliterateUmlauts(input), input)
    }

    func testSplitUnderscoreLeavesTextWithoutUnderscoresIdentical() {
        let input = "Wichtig ist nur"
        XCTAssertEqual(LocalTextTransformer.splitUnderscore(input), input)
    }

    func testLowercaseLeavesAlreadyLowercaseTextUnchanged() {
        let input = "wichtig ist nur"
        XCTAssertEqual(LocalTextTransformer.lowercase(input), input)
    }

    func testUppercaseLeavesAlreadyUppercaseTextUnchanged() {
        let input = "WICHTIG"
        XCTAssertEqual(LocalTextTransformer.uppercase(input), input)
    }

    func testJoinLinesLeavesSingleLineUnchanged() {
        let input = "Wichtig ist nur"
        XCTAssertEqual(LocalTextTransformer.joinLines(input), input)
    }

    // MARK: - slugify

    func testSlugifyLowercasesAndJoins() {
        XCTAssertEqual(LocalTextTransformer.slugify("Wichtig ist nur"), "wichtig_ist_nur")
    }

    func testSlugifyTransliteratesUmlauts() {
        XCTAssertEqual(LocalTextTransformer.slugify("Über uns"), "ueber_uns")
    }
}
