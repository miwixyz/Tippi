import XCTest
@testable import Tippi

/// Prüft die Versionsweiche für den Namen der Freigabe-Liste in Datenschutz & Sicherheit.
///
/// Warum: Tippi läuft ab macOS 15. Bis macOS 26 heißt die Liste „Bedienungshilfen“,
/// ab macOS 27 „Gerätesteuerung und Datenzugriff“. Ein falscher Name schickt Nutzer zu
/// einem Eintrag, den es auf ihrem Mac nicht gibt (Tippi 2.9.0 nannte die Grenze „macOS 26+“).
final class AccessibilityListNameTests: XCTestCase {

    func testUsesOldNameBeforeMacOS27() {
        XCTAssertEqual(AccessibilityListName.name(majorVersion: 15),
                       String(localized: "permissions.accessibilityList.legacy"))
        XCTAssertEqual(AccessibilityListName.name(majorVersion: 26),
                       String(localized: "permissions.accessibilityList.legacy"))
    }

    func testUsesNewNameFromMacOS27() {
        XCTAssertEqual(AccessibilityListName.name(majorVersion: 27),
                       String(localized: "permissions.accessibilityList.current"))
        XCTAssertEqual(AccessibilityListName.name(majorVersion: 28),
                       String(localized: "permissions.accessibilityList.current"))
    }

    func testBothNamesAreTranslated() {
        // Ein fehlender Schlüssel käme als Schlüsselname zurück.
        XCTAssertFalse(AccessibilityListName.name(majorVersion: 15).hasPrefix("permissions."))
        XCTAssertFalse(AccessibilityListName.name(majorVersion: 27).hasPrefix("permissions."))
    }

    func testTextInsertsNameAndLeavesNoPlaceholder() {
        let keys: [String.LocalizationValue] = [
            "autocomplete.error.accessibility", "autocomplete.error.tap",
            "setup.accessibility.title", "setup.accessibility.body", "settings.hotkeys.tip1",
            "settings.help.troubleBody", "settings.help.snippetsBody",
            "error.accessibility.hotkey", "error.accessibility.snippets", "error.accessibility.selection",
        ]
        for key in keys {
            let text = AccessibilityListName.text(key)
            XCTAssertFalse(text.contains("%"), "Platzhalter übrig: \(text)")
            XCTAssertTrue(text.contains(AccessibilityListName.name()), "Name fehlt: \(text)")
            XCTAssertFalse(text.contains("macOS 26+"), "Falsche Versionsgrenze: \(text)")
        }
    }
}
