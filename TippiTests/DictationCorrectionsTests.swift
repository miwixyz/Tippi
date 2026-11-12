import XCTest
@testable import Tippi

@MainActor
final class DictationCorrectionsTests: XCTestCase {
    private let suites = ThrowawayDefaults()

    func testConfirmationPersistsOnlySelectedPhraseAndRemovalSurvivesReload() throws {
        let defaults = suites.make()
        let corrections = DictationCorrections(defaults: defaults)
        XCTAssertFalse(corrections.enabled)
        let transcript = "Meine Notiz: Die Schrift gibt es bei Google Fonds."
        corrections.offer(transcript)
        XCTAssertNil(corrections.recent)

        corrections.setEnabled(true)
        corrections.offer(transcript)
        let rule = try XCTUnwrap(DictationCorrections.Rule(heard: "Google Fonds", replacement: "Google Fonts"))
        XCTAssertEqual(corrections.apply(to: transcript), transcript)
        XCTAssertTrue(corrections.save(rule))

        let reloaded = DictationCorrections(defaults: defaults)
        XCTAssertNil(reloaded.recent)
        XCTAssertEqual(reloaded.rules, [rule])
        XCTAssertEqual(reloaded.apply(to: "Bei Google Fonds, neben den Fonds."),
                       "Bei Google Fonts, neben den Fonds.")
        reloaded.remove(rule)
        XCTAssertTrue(DictationCorrections(defaults: defaults).rules.isEmpty)
    }

    func testContextRequiredAndUnknownPhraseCannotBeRemembered() throws {
        let corrections = DictationCorrections(defaults: suites.make())
        corrections.setEnabled(true)
        corrections.offer("Ich benutze Cotti für meine Notizen.")
        XCTAssertNil(DictationCorrections.Rule(heard: "Cotti", replacement: "Qotti"))
        XCTAssertNil(DictationCorrections.Rule(heard: "Cotti !", replacement: "Qotti"))
        XCTAssertNil(DictationCorrections.Rule(heard: "benutze Cotti", replacement: "Qotti\nopen"))
        let unrelated = try XCTUnwrap(DictationCorrections.Rule(heard: "Starte Cotti", replacement: "Starte Qotti"))
        XCTAssertFalse(corrections.save(unrelated))
        let scoped = try XCTUnwrap(DictationCorrections.Rule(heard: "benutze Cotti", replacement: "benutze Qotti"))
        XCTAssertTrue(corrections.save(scoped))
        XCTAssertEqual(corrections.apply(to: "Ich benutze Cotti. Ich rufe Frau Cotti an."),
                       "Ich benutze Qotti. Ich rufe Frau Cotti an.")
    }

    func testDisablingClearsExcerptAndStopsReplacementUntilEnabledAgain() throws {
        let corrections = DictationCorrections(defaults: suites.make())
        corrections.setEnabled(true)
        corrections.offer("Google Fonds öffnen")
        let rule = try XCTUnwrap(DictationCorrections.Rule(heard: "Google Fonds", replacement: "Google Fonts"))
        XCTAssertTrue(corrections.save(rule))

        corrections.setEnabled(false)
        XCTAssertNil(corrections.recent)
        XCTAssertEqual(corrections.apply(to: "Google Fonds öffnen"), "Google Fonds öffnen")
        corrections.setEnabled(true)
        XCTAssertEqual(corrections.apply(to: "Google Fonds öffnen"), "Google Fonts öffnen")
    }
}
