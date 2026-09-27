import AppKit
import XCTest
@testable import Tippi

/// Settings/UI fixes from the 2026-09-27 audit (group D).
final class UIAuditFixTests: XCTestCase {

    // MARK: - Global hot key recorder

    func testShiftOrOptionAloneIsRejected() {
        // ⇧A would take the capital A away from every app; ⌥L is `@` on German layouts.
        XCTAssertFalse(HotkeyRecorderField.isAcceptableGlobalHotkey(keyCode: 0, modifiers: [.shift]))
        XCTAssertFalse(HotkeyRecorderField.isAcceptableGlobalHotkey(keyCode: 37, modifiers: [.option]))
    }

    func testEverydayCommandShortcutsAreRejected() {
        for key: UInt16 in [8, 9, 7, 6, 12, 13, 48, 49] {   // C V X Z Q W Tab Space
            XCTAssertFalse(HotkeyRecorderField.isAcceptableGlobalHotkey(keyCode: key, modifiers: [.command]), "\(key)")
        }
    }

    func testRealHotkeysAreAccepted() {
        XCTAssertTrue(HotkeyRecorderField.isAcceptableGlobalHotkey(keyCode: 17, modifiers: [.option, .command]))  // ⌥⌘T
        XCTAssertTrue(HotkeyRecorderField.isAcceptableGlobalHotkey(keyCode: 8, modifiers: [.command, .option]))   // ⌥⌘C
        XCTAssertTrue(HotkeyRecorderField.isAcceptableGlobalHotkey(keyCode: 46, modifiers: [.control, .option, .command]))
    }

    // MARK: - Toast position

    private let visible = NSRect(x: 0, y: 80, width: 1440, height: 800)   // Dock below y = 80
    private let size = NSSize(width: 200, height: 30)

    func testToastBelowCursorWhenThereIsRoom() {
        let origin = ToastWindowController.origin(cursor: NSPoint(x: 700, y: 500), size: size, visible: visible)
        XCTAssertEqual(origin, NSPoint(x: 600, y: 456))
    }

    func testToastFlipsAboveCursorAtTheBottomEdge() {
        let origin = ToastWindowController.origin(cursor: NSPoint(x: 700, y: 90), size: size, visible: visible)
        XCTAssertEqual(origin.y, 104)
        XCTAssertGreaterThanOrEqual(origin.y, visible.minY)
    }

    func testToastStaysOnScreenHorizontally() {
        let left = ToastWindowController.origin(cursor: NSPoint(x: 5, y: 500), size: size, visible: visible)
        let right = ToastWindowController.origin(cursor: NSPoint(x: 1439, y: 500), size: size, visible: visible)
        XCTAssertEqual(left.x, 0)
        XCTAssertEqual(right.x, 1240)
    }
}
