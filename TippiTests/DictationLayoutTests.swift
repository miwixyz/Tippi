import XCTest
@testable import Tippi

/// Diktat „Absätze und Satzzeichen" und „Diktat für Mails": rein regelbasiertes
/// Layout, Weiche und Mail-Hotkey. Einstellungen nur über `DictationSettings.store`.
@MainActor
final class DictationLayoutTests: XCTestCase {
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

    // MARK: - Michaels Beispiele

    /// Real 2026-09-30 (Testversion): kam ohne einen einzigen Umbruch an.
    func testGreetingBodyAndEmbeddedClosing() {
        XCTAssertEqual(DictationLayout.format(
            "Hallo lieber Mensch, ich möchte dich kurz nachfragen, ob du meine Mail erhalten hast. Vielen Dank und liebe Grüße."),
            "Hallo lieber Mensch,\n\nich möchte dich kurz nachfragen, ob du meine Mail erhalten hast.\n\nVielen Dank und liebe Grüße.")
    }

    func testEachSentenceOnItsOwnLineAndClosingApart() {
        XCTAssertEqual(DictationLayout.format(
            "Wir haben eure Seiten nun auf das neue Design umgestellt. "
                + "Wenn ihr Fragen dazu habt, könnt ihr euch gerne an uns wenden. Liebe Grüße."),
            "Wir haben eure Seiten nun auf das neue Design umgestellt.\n"
                + "Wenn ihr Fragen dazu habt, könnt ihr euch gerne an uns wenden.\n\nLiebe Grüße.")
    }

    func testAnnouncementGetsAColon() {
        XCTAssertEqual(DictationLayout.format("Die Filme werden mit folgenden Nummern angelegt."),
                       "Die Filme werden mit folgenden Nummern angelegt:")
        XCTAssertEqual(DictationLayout.format("Please note the following. Bring your ID."),
                       "Please note the following:\nBring your ID.")
    }

    func testChatSentenceStaysUnchanged() {
        for text in ["Bin gleich da.", "Hallo, wie geht's?", "Ich bin in zehn Minuten da, kannst du Kaffee machen?"] {
            XCTAssertEqual(DictationLayout.format(text), text)
        }
    }

    /// NLTokenizer trennt nach „3." und „Prof." — wieder zusammengefügt.
    func testOrdinalsAndAbbreviationsDoNotSplit() {
        XCTAssertEqual(DictationLayout.format("Treffen wir uns am 3. Oktober um 10 Uhr? Dr. Meier kommt auch."),
                       "Treffen wir uns am 3. Oktober um 10 Uhr?\nDr. Meier kommt auch.")
        XCTAssertEqual(DictationLayout.format("Bitte z. B. die Belege mitbringen. Prof. Weber kommt ca. 10 Minuten später."),
                       "Bitte z. B. die Belege mitbringen.\nProf. Weber kommt ca. 10 Minuten später.")
    }

    // MARK: - Anrede und Gruß

    func testGreetingsInThreeLanguages() {
        XCTAssertEqual(DictationLayout.format("Hi Tom, thanks for the reply. Best regards, Michael"),
                       "Hi Tom,\n\nthanks for the reply.\n\nBest regards, Michael")
        XCTAssertEqual(DictationLayout.format("Hola Carla, gracias por la información. Un saludo."),
                       "Hola Carla,\n\ngracias por la información.\n\nUn saludo.")
        XCTAssertEqual(DictationLayout.format("Sehr geehrte Frau Müller, anbei das Angebot. Mit freundlichen Grüßen"),
                       "Sehr geehrte Frau Müller,\n\nanbei das Angebot.\n\nMit freundlichen Grüßen")
    }

    /// „Liebe ist …" ist keine Anrede; ein langer letzter Satz mit „Grüße" keine Grußformel.
    func testNoFalseGreetingOrClosing() {
        XCTAssertEqual(DictationLayout.format("Liebe ist alles, was zählt. Das weiß jeder."),
                       "Liebe ist alles, was zählt.\nDas weiß jeder.")
        XCTAssertEqual(DictationLayout.format("Wir waren gestern da. Sag deiner Mutter bitte liebe Grüße von mir und auch von Anna und Paul."),
                       "Wir waren gestern da.\nSag deiner Mutter bitte liebe Grüße von mir und auch von Anna und Paul.")
    }

    func testEmbeddedClosingVariants() {
        XCTAssertEqual(DictationLayout.format("Das passt so. Danke und viele Grüße aus München."),
                       "Das passt so.\n\nDanke und viele Grüße aus München.")
        XCTAssertEqual(DictationLayout.format("Sounds good. Thanks and best, Tom."),
                       "Sounds good.\n\nThanks and best, Tom.")
    }

    // MARK: - Weiche

    func testLayoutWanted() {
        XCTAssertFalse(DictationLayout.layoutWanted(source: .standard, toggle: false, targetIsTerminal: false))
        XCTAssertTrue(DictationLayout.layoutWanted(source: .standard, toggle: true, targetIsTerminal: false))
        XCTAssertTrue(DictationLayout.layoutWanted(source: .mail, toggle: false, targetIsTerminal: false))
        // Terminal / Enter-Liste: nie, auch nicht beim Mail-Diktat.
        XCTAssertFalse(DictationLayout.layoutWanted(source: .mail, toggle: true, targetIsTerminal: true))
        XCTAssertFalse(DictationLayout.layoutWanted(source: .standard, toggle: true, targetIsTerminal: true))
    }

    func testOptionIsOffByDefaultAndNoLongerTouchesThePrompt() {
        XCTAssertFalse(DictationSettings.layoutEnabled)
        DictationSettings.layoutEnabled = true
        XCTAssertTrue(DictationSettings.layoutEnabled)
        XCTAssertFalse(DictationSettings.effectivePostProcessPrompt.contains("Layout"))
    }

    // MARK: - Hotkey „Diktat für Mails"

    func testMailHotkeyDefaultsAndRoundTrip() {
        XCTAssertTrue(MailDictationSettings.isEnabled)
        XCTAssertEqual(MailDictationSettings.combo, MailDictationSettings.defaultCombo)
        XCTAssertEqual(MailDictationSettings.defaultCombo.displayString, "⌃⌥⌘B")
        let other = KeyCombo(keyCode: 11, modifiers: [.control, .option, .shift, .command])
        MailDictationSettings.combo = other
        XCTAssertEqual(MailDictationSettings.combo, other)
        XCTAssertNotNil(DictationSettings.store.data(forKey: "dictation.mailHotkeyCombo.v1"))
    }

    /// Der Standard kollidiert mit keinem Tippi-Standard und nicht mit Michaels Hyper-Kürzeln.
    func testDefaultIsFreeAndConflictsAreNamed() {
        let defaults: [(name: String, combo: KeyCombo)] = [
            ("main", .default), ("safety", MailDictationSettings.safetyCombo), ("dictation", .dictationDefault),
            ("translate", .translateDefault), ("emoji", .emojiDefault), ("notes", .notesDefault),
            ("ocr", KeyCombo(keyCode: 19, modifiers: [.option, .command])),
            ("hyper", KeyCombo(keyCode: 17, modifiers: [.control, .option, .shift, .command])),
        ]
        XCTAssertNil(MailDictationSettings.conflict(of: MailDictationSettings.defaultCombo, in: defaults))
        XCTAssertEqual(MailDictationSettings.conflict(of: .notesDefault, in: defaults), "notes")
        XCTAssertEqual(MailDictationSettings.conflict(of: MailDictationSettings.safetyCombo, in: defaults), "safety")
    }
}
