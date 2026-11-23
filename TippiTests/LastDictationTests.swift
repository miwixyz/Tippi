import XCTest
@testable import Tippi

/// „Letztes Diktat erneut einfügen“ (2026-11-23, docs/SECURE-DESIGN-letztes-diktat.md): nur im Speicher,
/// höchstens 30 Minuten, ein Eintrag, nie aus Notiz-/Antwort-Diktat oder Passwortfeld.
@MainActor
final class LastDictationTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private var suite = ""
    private var oldStore: UserDefaults!

    override func setUp() async throws {
        suite = "tippi.lastdictation.tests.\(UUID().uuidString)"
        oldStore = LastDictationSettings.store
        LastDictationSettings.store = UserDefaults(suiteName: suite)!
        LastDictation.shared.clear()
        LastDictation.shared.now = { [unowned self] in clock }
    }

    override func tearDown() async throws {
        LastDictationSettings.store.removePersistentDomain(forName: suite)
        LastDictationSettings.store = oldStore
        LastDictation.shared.now = { Date() }
        LastDictation.shared.clear()
    }

    func testRecallReturnsWhatWasRemembered() {
        LastDictation.shared.remember("Hallo Welt")
        XCTAssertEqual(LastDictation.shared.recall(), "Hallo Welt")
        XCTAssertEqual(LastDictation.shared.recall(), "Hallo Welt", "recall does not use it up: a second press works too")
    }

    func testNothingRememberedMeansNil() {
        XCTAssertNil(LastDictation.shared.recall())
    }

    func testExpiresAfterThirtyMinutes() {
        LastDictation.shared.remember("Hallo")
        clock = clock.addingTimeInterval(LastDictation.lifetime)
        XCTAssertEqual(LastDictation.shared.recall(), "Hallo", "exactly at the limit still counts")
        clock = clock.addingTimeInterval(1)
        XCTAssertNil(LastDictation.shared.recall())
        clock = clock.addingTimeInterval(-LastDictation.lifetime)
        XCTAssertNil(LastDictation.shared.recall(), "once expired it is gone, not just hidden")
    }

    func testNewDictationReplacesTheOldOne() {
        LastDictation.shared.remember("alt")
        LastDictation.shared.remember("neu")
        XCTAssertEqual(LastDictation.shared.recall(), "neu")
    }

    func testEmptyDictationClearsInsteadOfKeepingTheOldOne() {
        LastDictation.shared.remember("alt")
        LastDictation.shared.remember("  \n ")
        XCTAssertNil(LastDictation.shared.recall())
    }

    func testTooLongTextIsNotKept() {
        LastDictation.shared.remember("alt")
        LastDictation.shared.remember(String(repeating: "a", count: LastDictation.maxCharacters + 1))
        XCTAssertNil(LastDictation.shared.recall())
        LastDictation.shared.remember(String(repeating: "a", count: LastDictation.maxCharacters))
        XCTAssertNotNil(LastDictation.shared.recall())
    }

    func testClear() {
        LastDictation.shared.remember("x")
        LastDictation.shared.clear()
        XCTAssertNil(LastDictation.shared.recall())
    }

    func testNotesAndReplyDictationKeepNothing() {
        LastDictation.shared.rememberDictation("Notiz", source: .inbox, isSecure: false)
        LastDictation.shared.rememberDictation("Antwort", source: .reply, isSecure: false)
        XCTAssertNil(LastDictation.shared.recall())
    }

    func testStandardAndMailDictationAreKept() {
        LastDictation.shared.rememberDictation("normal", source: .standard, isSecure: false)
        XCTAssertEqual(LastDictation.shared.recall(), "normal")
        LastDictation.shared.rememberDictation("Brief", source: .mail, isSecure: false)
        XCTAssertEqual(LastDictation.shared.recall(), "Brief")
    }

    func testNothingIsKeptWhileSecureInputIsOn() {
        LastDictation.shared.rememberDictation("Passwort123", source: .standard, isSecure: true)
        XCTAssertNil(LastDictation.shared.recall())
    }

    func testOffByTheSwitchKeepsNothing() {
        LastDictationSettings.isEnabled = false
        LastDictation.shared.rememberDictation("x", source: .standard, isSecure: false)
        XCTAssertNil(LastDictation.shared.recall())
    }

    func testSwitchingOffDeletesWhatWasKept() {
        LastDictation.shared.remember("x")
        LastDictationSettings.isEnabled = false
        XCTAssertNil(LastDictation.shared.recall())
        LastDictationSettings.isEnabled = true
        XCTAssertNil(LastDictation.shared.recall(), "switching on does not bring it back")
    }

    func testOnByDefaultWithTheDefaultCombo() {
        XCTAssertTrue(LastDictationSettings.isEnabled)
        XCTAssertEqual(LastDictationSettings.combo, .lastDictationDefault)
        XCTAssertEqual(KeyCombo.lastDictationDefault.displayString, "⌃⌥⌘V")
        let custom = KeyCombo(keyCode: 8, modifiers: [.control, .option, .command])
        LastDictationSettings.combo = custom
        XCTAssertEqual(LastDictationSettings.combo, custom)
    }

    func testDefaultComboCollidesWithNoOtherTippiHotkey() {
        let taken = MailDictationSettings.takenCombos().filter { $0.name != String(localized: "hotkeyName.lastDictation") }
        XCTAssertNil(MailDictationSettings.conflict(of: .lastDictationDefault, in: taken))
    }

    func testOtherHotkeysSeeTheNewOneAsTaken() {
        let names = MailDictationSettings.takenCombos().map(\.name)
        XCTAssertTrue(names.contains(String(localized: "hotkeyName.lastDictation")))
    }
}
