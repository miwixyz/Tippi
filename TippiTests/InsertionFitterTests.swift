import XCTest
@testable import Tippi

/// "Einfügen passend zum Cursor" (2026-10-27): the dictation's edges adapt to
/// the text around the cursor. Pure rules — nothing here touches
/// Accessibility or preferences except `DictationSettings` via a throwaway suite.
final class InsertionFitterTests: XCTestCase {

    private func fit(_ text: String, _ before: String, _ after: String = "") -> String {
        InsertionFitter.fit(text, before: before, after: after)
    }

    // MARK: Sentence start

    func testEmptyFieldCapitalizesAndKeepsPeriod() {
        XCTAssertEqual(fit("und dann gehen wir.", ""), "Und dann gehen wir.")
        XCTAssertEqual(fit("see you tomorrow.", ""), "See you tomorrow.")
    }

    func testAfterSentenceEndAddsSpaceAndCapital() {
        XCTAssertEqual(fit("das klappt.", "Ich bin da."), " Das klappt.")
        XCTAssertEqual(fit("that works.", "I'm here!"), " That works.")
        XCTAssertEqual(fit("kommst du?", "Fertig? "), "Kommst du?", "space already there — none added")
    }

    func testAfterLineBreakCapitalizesWithoutSpace() {
        XCTAssertEqual(fit("viele Grüße", "Hallo Patrik,\n"), "Viele Grüße")
    }

    // MARK: Mid-sentence

    func testMidSentenceLowercasesFunctionWordGerman() {
        XCTAssertEqual(fit("Und dann noch das Plakat.", "Ich schicke dir die Liste"), " und dann noch das Plakat.")
    }

    func testMidSentenceLowercasesFunctionWordEnglish() {
        XCTAssertEqual(fit("And the poster.", "I'll send the list,"), " and the poster.")
    }

    func testMidSentenceKeepsNounsAndPoliteForms() {
        XCTAssertEqual(fit("Montag passt.", "Ich glaube"), " Montag passt.", "German noun keeps its capital")
        XCTAssertEqual(fit("Sie haben recht.", "Ich denke,"), " Sie haben recht.", "„Sie“ is not lowercased")
        XCTAssertEqual(fit("I agree.", "Honestly"), " I agree.")
    }

    // MARK: After a colon

    func testAfterColonKeepsCaseAndAddsSpace() {
        XCTAssertEqual(fit("Bitte bis Freitag.", "Wichtig:"), " Bitte bis Freitag.")
        XCTAssertEqual(fit("drei Punkte.", "Folgendes:"), " drei Punkte.")
        XCTAssertEqual(fit("the list.", "Attached:"), " the list.")
    }

    // MARK: Before punctuation / continuing text

    func testBeforePunctuationDropsPeriodAndAddsNoSpace() {
        XCTAssertEqual(fit("das neue Plakat.", "Ich brauche ", ", bitte bis Montag."), "das neue Plakat")
        XCTAssertEqual(fit("the new poster.", "I need ", "."), "the new poster")
    }

    func testBeforeLowercaseContinuationDropsPeriodAndAddsSpace() {
        XCTAssertEqual(fit("das neue Plakat.", "Ich brauche ", "noch heute."), "das neue Plakat ")
    }

    func testAbbreviationKeepsPeriod() {
        XCTAssertEqual(fit("z. B. Plakate usw.", "Material ", "noch heute"), "z. B. Plakate usw. ")
    }

    func testBeforeCapitalizedNextSentenceKeepsPeriodAndAddsSpace() {
        XCTAssertEqual(fit("Das war es.", "", "Danke!"), "Das war es. ")
    }

    // MARK: Spacing details

    func testNoSpaceAfterOpeningBracketOrQuote() {
        XCTAssertEqual(fit("siehe unten", "Plakat ("), "siehe unten")
        XCTAssertEqual(fit("Kinostart", "Titel „"), "Kinostart")
    }

    func testHyphenJoinsWordButDashGetsSpace() {
        XCTAssertEqual(fit("Mail", "Schick mir die E-"), "Mail")
        XCTAssertEqual(fit("und morgen", "Heute gut -"), " und morgen")
    }

    func testDictationStartingWithPunctuationGetsNoSpace() {
        XCTAssertEqual(fit(", oder?", "Das passt"), ", oder?")
    }

    func testWhitespaceAroundDictationIsTrimmed() {
        XCTAssertEqual(fit("  hallo  ", ""), "Hallo")
    }

    func testEmptyDictationStaysAsIs() {
        XCTAssertEqual(fit("   ", "Text"), "   ")
    }

    // MARK: Unreadable field / decision

    func testUnreadableFieldLeavesTextUnchanged() {
        XCTAssertEqual(InsertionFitter.fit("und dann.", around: nil), "und dann.")
    }

    func testFieldTextVariantMatchesPlainVariant() {
        XCTAssertEqual(InsertionFitter.fit("und dann.", around: FieldText(before: "Gut.", after: "")), " Und dann.")
    }

    func testSliceCutsAroundSelectionInUTF16() {
        // „ü“ and the emoji count as UTF-16 units, the way AX reports ranges.
        let value = "Grüße 👋 an alle"
        let selected = (value as NSString).range(of: "an")
        let field = FocusedFieldReader.slice(value, range: CFRange(location: selected.location, length: selected.length))
        XCTAssertEqual(field, FieldText(before: "Grüße 👋 ", after: " alle"))
    }

    func testSliceRejectsRangeOutsideText() {
        XCTAssertNil(FocusedFieldReader.slice("kurz", range: CFRange(location: 3, length: 5)))
        XCTAssertNil(FocusedFieldReader.slice("kurz", range: CFRange(location: -1, length: 0)))
    }

    func testFitWantedNeverInTerminalsOrWhenOff() {
        XCTAssertTrue(DictationSettings.fitWanted(toggle: true, targetBundleID: "com.apple.mail"))
        XCTAssertTrue(DictationSettings.fitWanted(toggle: true, targetBundleID: nil))
        XCTAssertFalse(DictationSettings.fitWanted(toggle: false, targetBundleID: "com.apple.mail"))
        XCTAssertFalse(DictationSettings.fitWanted(toggle: true, targetBundleID: "com.apple.Terminal"))
        XCTAssertFalse(DictationSettings.fitWanted(toggle: true, targetBundleID: "com.microsoft.VSCode"))
    }
}

/// The setting itself: on by default, and the switch sticks.
@MainActor
final class InsertionFitterSettingTests: XCTestCase {
    // Throwaway suite, never `.standard` — the test host IS the installed app.
    private let suites = ThrowawayDefaults()

    override func setUp() {
        super.setUp()
        DictationSettings.store = suites.make()
    }

    override func tearDown() {
        DictationSettings.store = .standard
        suites.removeAll()
        super.tearDown()
    }

    func testOnByDefault() {
        XCTAssertTrue(DictationSettings.fitInsertionEnabled)
    }

    func testCanBeSwitchedOff() {
        DictationSettings.fitInsertionEnabled = false
        XCTAssertFalse(DictationSettings.fitInsertionEnabled)
        DictationSettings.fitInsertionEnabled = true
        XCTAssertTrue(DictationSettings.fitInsertionEnabled)
    }
}
