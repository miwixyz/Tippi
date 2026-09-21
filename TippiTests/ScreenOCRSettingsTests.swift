import XCTest
@testable import Tippi

/// Prüft die Voreinstellungen der Bildschirm-Texterkennung.
///
/// Warum gerade diese: Beide Standardwerte sind **Sicherheitsentscheidungen**,
/// keine Geschmacksfragen. Sie stehen in `docs/SECURE-DESIGN-screen-ocr.md` und
/// ließen sich beim Aufräumen versehentlich umdrehen, ohne dass es jemandem
/// auffiele — eine Funktion, die ab Werk an ist, fragt beim ersten Start nach
/// einer Dauervollmacht für den Bildschirm.
@MainActor
final class ScreenOCRSettingsTests: XCTestCase {

    private let keys = [
        "screenOCR.hotkey.enabled",
        "screenOCR.hotkeyCombo.v1",
        "screenOCR.concealFromClipboardHistory",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    /// Ab Werk AUS. Die Funktion verlangt „Bildschirmaufnahme" — eine
    /// Dauervollmacht, die Tippi zusammen mit dem vorhandenen
    /// Bedienungshilfen-Zugriff zu „sieht alles, schreibt überall" macht.
    /// Wer sie nicht braucht, soll sie nie erteilen müssen.
    func testIsDisabledByDefault() {
        XCTAssertFalse(ScreenOCRSettings.isEnabled,
                       "Bildschirm-OCR muss ab Werk aus sein — sie verlangt eine Dauervollmacht.")
    }

    /// Ab Werk AUS, aber aus dem umgekehrten Grund: Dauerhaftes Verbergen
    /// nähme den Text auch aus der eigenen Verlaufssuche, wo er meist gesucht
    /// wird. Der Schalter ist für den Moment gedacht, nicht für den Alltag.
    func testConcealIsOffByDefault() {
        XCTAssertFalse(ScreenOCRSettings.concealFromClipboardHistory,
                       "Verbergen ist der Ausnahmefall, nicht die Voreinstellung.")
    }

    func testSettingsRoundTrip() {
        ScreenOCRSettings.isEnabled = true
        ScreenOCRSettings.concealFromClipboardHistory = true
        XCTAssertTrue(ScreenOCRSettings.isEnabled)
        XCTAssertTrue(ScreenOCRSettings.concealFromClipboardHistory)

        ScreenOCRSettings.isEnabled = false
        ScreenOCRSettings.concealFromClipboardHistory = false
        XCTAssertFalse(ScreenOCRSettings.isEnabled)
        XCTAssertFalse(ScreenOCRSettings.concealFromClipboardHistory)
    }

    /// Der Standard-Hotkey darf nicht mit den fünf bestehenden kollidieren.
    func testDefaultComboDiffersFromOtherHotkeys() {
        let ocr = ScreenOCRSettings.combo
        for other in [KeyCombo.translateDefault, .notesDefault] {
            XCTAssertFalse(ocr.keyCode == other.keyCode && ocr.modifiers == other.modifiers,
                           "Standard-Hotkey kollidiert mit einem bestehenden.")
        }
    }

    /// Ein eigener Hotkey muss die Voreinstellung überleben.
    func testComboPersists() {
        let custom = KeyCombo(keyCode: 20, modifiers: [.control, .shift])
        ScreenOCRSettings.combo = custom
        XCTAssertEqual(ScreenOCRSettings.combo.keyCode, custom.keyCode)
        XCTAssertEqual(ScreenOCRSettings.combo.modifiers, custom.modifiers)
    }
}
