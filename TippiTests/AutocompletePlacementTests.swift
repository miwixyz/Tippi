import CoreGraphics
import XCTest
@testable import Tippi

/// Platzierung und Darstellung des Vorschlags (Michael 2026-10-13: „schlecht
/// erkennbar", schwebte über der Zeile, verschwand beim Bildschirmfoto).
@MainActor
final class AutocompletePlacementTests: XCTestCase {
    // MARK: - Cursor-Rechteck

    /// Gemessene TextEdit-Werte (AX): Cursor y 430, Zeichen davor y 444, Höhe 14.
    func testTextEditCaretTakesLineOfCharacterBefore() {
        let zero = CGRect(x: 1439.92, y: 430, width: 0, height: 14)
        let char = CGRect(x: 1433.25, y: 444, width: 6.67, height: 14)
        let caret = AutocompleteGeometry.caret(zeroLength: zero, charBefore: char)
        XCTAssertEqual(caret, CGRect(x: 1439.92, y: 444, width: 0, height: 14))
    }

    /// Zeichen davor steht woanders (Zeilenumbruch) → Cursor-Rechteck gilt.
    func testCharacterOnOtherLineIsIgnored() {
        let zero = CGRect(x: 100, y: 500, width: 0, height: 14)
        let char = CGRect(x: 600, y: 514, width: 0, height: 14)
        XCTAssertEqual(AutocompleteGeometry.caret(zeroLength: zero, charBefore: char),
                       CGRect(x: 100, y: 500, width: 0, height: 14))
    }

    func testOnlyCharacterBefore() {
        let char = CGRect(x: 10, y: 20, width: 6, height: 14)
        XCTAssertEqual(AutocompleteGeometry.caret(zeroLength: nil, charBefore: char),
                       CGRect(x: 16, y: 20, width: 0, height: 14))
    }

    func testNothingPlausible() {
        XCTAssertNil(AutocompleteGeometry.caret(zeroLength: nil, charBefore: nil))
    }

    // MARK: - Bildschirmfoto

    func testScreenshotShortcutsKeepSuggestion() {
        let cmdShift: CGEventFlags = [.maskCommand, .maskShift]
        XCTAssertEqual(AutocompleteKeyDecision.screenshotShortcut(keyCode: 20, flags: cmdShift), .wholeScreen)
        XCTAssertEqual(AutocompleteKeyDecision.screenshotShortcut(keyCode: 21, flags: cmdShift), .withPick)
        XCTAssertEqual(AutocompleteKeyDecision.screenshotShortcut(keyCode: 23, flags: cmdShift), .withPick)
        XCTAssertEqual(AutocompleteKeyDecision.screenshotShortcut(keyCode: 21, flags: cmdShift.union(.maskControl)), .withPick)
    }

    func testOtherShortcutsAreNoScreenshot() {
        XCTAssertNil(AutocompleteKeyDecision.screenshotShortcut(keyCode: 21, flags: .maskCommand))        // ⌘4
        XCTAssertNil(AutocompleteKeyDecision.screenshotShortcut(keyCode: 21, flags: .maskShift))          // $
        XCTAssertNil(AutocompleteKeyDecision.screenshotShortcut(keyCode: 9, flags: [.maskCommand, .maskShift])) // ⇧⌘V
        XCTAssertNil(AutocompleteKeyDecision.screenshotShortcut(keyCode: 21, flags: [.maskCommand, .maskShift, .maskAlternate]))
    }

    func testScreenshotClickIsConsumedOnce() {
        let bridge = AutocompleteTapBridge()
        XCTAssertFalse(bridge.consumeScreenshotClick())
        bridge.armScreenshotPick(true)
        XCTAssertTrue(bridge.consumeScreenshotClick())
        XCTAssertFalse(bridge.consumeScreenshotClick())
        bridge.armScreenshotPick(true)
        bridge.armScreenshotPick(false)   // andere Taste dazwischen
        XCTAssertFalse(bridge.consumeScreenshotClick())
    }

    // MARK: - Anzeige

    func testDisplayTextKeepsOneLeadingSpace() {
        XCTAssertEqual(AutocompleteSuggestionView.displayText(" passiert? "), " passiert?")
        XCTAssertEqual(AutocompleteSuggestionView.displayText("  das"), " das")
        XCTAssertEqual(AutocompleteSuggestionView.displayText("iert"), "iert")
    }
}
