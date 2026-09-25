import XCTest
@testable import Tippi

/// `Tipi → Tippi` entries in the custom-words list. Pure functions — no
/// preferences touched, so no `ThrowawayDefaults` needed.
@MainActor
final class CustomWordVariantsTests: XCTestCase {
    private typealias Variants = CustomWordVariants

    // MARK: - Parser

    func testAllThreeArrowsParseToTheSameRule() {
        let expected = Variants.Entry.rule(.init(variants: ["Tipi"], target: "Tippi"))
        XCTAssertEqual(Variants.parse("Tipi → Tippi"), expected)
        XCTAssertEqual(Variants.parse("Tipi -> Tippi"), expected)
        XCTAssertEqual(Variants.parse("Tipi => Tippi"), expected)
    }

    func testWhitespaceAroundAndWithoutIsTolerated() {
        let expected = Variants.Entry.rule(.init(variants: ["Tipi"], target: "Tippi"))
        XCTAssertEqual(Variants.parse("Tipi→Tippi"), expected)
        XCTAssertEqual(Variants.parse("  Tipi   ->   Tippi  "), expected)
    }

    func testCommaSeparatedVariants() {
        XCTAssertEqual(
            Variants.parse("Tipi, Tippie ,  Tipy → Tippi"),
            .rule(.init(variants: ["Tipi", "Tippie", "Tipy"], target: "Tippi"))
        )
    }

    func testEmptySidesAreIgnored() {
        XCTAssertNil(Variants.parse("Tipi →"), "no target — nothing to enforce")
        XCTAssertNil(Variants.parse("   "))
        XCTAssertEqual(Variants.parse("→ Tippi"), .term("Tippi"), "no variant — just a glossary term")
        XCTAssertEqual(Variants.parse(" , , → Tippi"), .term("Tippi"))
        XCTAssertEqual(
            Variants.parse("Tipi, , → Tippi"),
            .rule(.init(variants: ["Tipi"], target: "Tippi")),
            "empty items between commas are dropped"
        )
    }

    func testPlainEntryStaysATermEvenWithComma() {
        XCTAssertEqual(Variants.parse("CINEWEB"), .term("CINEWEB"))
        XCTAssertEqual(Variants.parse("Müller, Meier & Co"), .term("Müller, Meier & Co"))
    }

    func testVariantIdenticalToTargetIsDropped() {
        XCTAssertEqual(Variants.parse("Tippi → Tippi"), .term("Tippi"))
        XCTAssertEqual(
            Variants.parse("tippi → Tippi"),
            .rule(.init(variants: ["tippi"], target: "Tippi")),
            "different case is a real correction, not a no-op"
        )
    }

    // MARK: - Replacement

    private let rules = ["Tipi → Tippi"]

    func testReplacesWholeWord() {
        XCTAssertEqual(Variants.apply(to: "Ich teste Tipi heute", entries: rules), "Ich teste Tippi heute")
    }

    func testCaseOfInputDoesNotMatterTargetIsExact() {
        XCTAssertEqual(Variants.apply(to: "tipi TIPI Tipi tIpI", entries: rules), "Tippi Tippi Tippi Tippi")
        XCTAssertEqual(Variants.apply(to: "cineweb ist toll", entries: ["cine web, cineweb → CINEWEB"]),
                       "CINEWEB ist toll")
    }

    func testPunctuationAroundIsKept() {
        XCTAssertEqual(Variants.apply(to: "Tipi, Tipi. (Tipi)! „Tipi“?", entries: rules),
                       "Tippi, Tippi. (Tippi)! „Tippi“?")
        XCTAssertEqual(Variants.apply(to: "Tipi's Idee", entries: rules), "Tippi's Idee")
    }

    func testWordPartsAreNotTouched() {
        XCTAssertEqual(Variants.apply(to: "Tipis Stipi Tipi2 xTipi", entries: rules), "Tipis Stipi Tipi2 xTipi")
    }

    func testUmlautsCountAsLetters() {
        // "ä" next to the variant is a letter, not a boundary.
        XCTAssertEqual(Variants.apply(to: "Tipiä äTipi Tipi", entries: rules), "Tipiä äTipi Tippi")
        // Umlaut inside the variant, case-insensitive across Ä/ä.
        XCTAssertEqual(Variants.apply(to: "ÄRGA und ärga", entries: ["ärga → Ärger"]), "Ärger und Ärger")
        // Umlaut in the target is inserted as written.
        XCTAssertEqual(Variants.apply(to: "Muller kommt", entries: ["Muller → Müller"]), "Müller kommt")
    }

    func testMultipleOccurrencesAndRules() {
        let entries = ["Tipi, Tippie → Tippi", "Cine Social → CineSocial", "CINEWEB"]
        XCTAssertEqual(
            Variants.apply(to: "Tipi und Tippie für Cine Social, dann wieder tipi.", entries: entries),
            "Tippi und Tippi für CineSocial, dann wieder Tippi."
        )
    }

    func testLongerVariantWinsAndReplacementsDoNotChain() {
        let entries = ["Tipi → Tippi", "Tipi App → Tippi-App", "Tippi → Falsch"]
        XCTAssertEqual(Variants.apply(to: "Die Tipi App", entries: entries), "Die Tippi-App")
        XCTAssertEqual(Variants.apply(to: "Tipi", entries: entries), "Tippi",
                       "a target must not be picked up by another rule in the same pass")
    }

    func testRegexCharactersInVariantAreLiteral() {
        XCTAssertEqual(Variants.apply(to: "C++ und Cxx", entries: ["C++ → Cpp"]), "Cpp und Cxx")
        XCTAssertEqual(Variants.apply(to: "a.b axb", entries: ["a.b → $1\\0"]), "$1\\0 axb",
                       "target is inserted literally, no template expansion")
    }

    func testNoRulesLeavesTextUntouched() {
        let text = "Tipi bleibt Tipi"
        XCTAssertEqual(Variants.apply(to: text, entries: []), text)
        XCTAssertEqual(Variants.apply(to: text, entries: ["CINEWEB", "Tippi"]), text,
                       "plain entries never rewrite anything")
    }

    // MARK: - Glossary

    func testGlossaryHasTargetsNotVariants() {
        let entries = ["CINEWEB", "Tipi, Tippie → Tippi", "Tipi →", "→ CineSocial", "Tippi"]
        XCTAssertEqual(Variants.glossaryTerms(from: entries), ["CINEWEB", "Tippi", "CineSocial"])
    }

    func testPromptGlossaryNeverNamesAVariant() {
        let prompt = DictationSettings.promptWithGlossary("BASE", customWords: ["CINEWEB", "Tipi → Tippi"])
        XCTAssertTrue(prompt.hasPrefix("BASE"))
        XCTAssertTrue(prompt.contains("CINEWEB, Tippi."))
        XCTAssertFalse(prompt.contains("Tipi "))
        XCTAssertFalse(prompt.contains("→"))
    }

    func testPromptWithoutTermsIsUnchanged() {
        XCTAssertEqual(DictationSettings.promptWithGlossary("BASE", customWords: []), "BASE")
        XCTAssertEqual(DictationSettings.promptWithGlossary("BASE", customWords: ["Tipi →"]), "BASE")
    }
}
