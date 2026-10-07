import XCTest
@testable import Tippi

/// Die Aktionsleiste erscheint nur nach einer Markierung, die der Nutzer selbst
/// gemacht hat — nicht, wenn eine App beim bloßen Anklicken eines Feldes den Inhalt
/// markiert (Erinnerungen, Uhrzeit „09:00“; Michael, 2026-10-07).
final class SelectionPopupGestureTests: XCTestCase {
    private func gesture(dx: CGFloat = 0, dy: CGFloat = 0, clicks: Int = 1, shift: Bool = false) -> Bool {
        SelectionPopupMonitor.isUserSelectionGesture(
            mouseDown: CGPoint(x: 100, y: 100),
            mouseUp: CGPoint(x: 100 + dx, y: 100 + dy),
            clickCount: clicks,
            shiftHeld: shift
        )
    }

    func testPlainClickIsNoSelectionGesture() {
        XCTAssertFalse(gesture())
        XCTAssertFalse(gesture(dx: 2, dy: 1), "Zittern beim Klicken ist kein Ziehen")
    }

    func testDragIsSelectionGesture() {
        XCTAssertTrue(gesture(dx: 30))
        XCTAssertTrue(gesture(dy: -12))
    }

    func testDoubleAndTripleClickAreSelectionGestures() {
        XCTAssertTrue(gesture(clicks: 2))
        XCTAssertTrue(gesture(clicks: 3))
    }

    func testShiftClickExtendsSelection() {
        XCTAssertTrue(gesture(shift: true))
    }

    func testMissingMouseDownCountsAsNoGesture() {
        XCTAssertFalse(SelectionPopupMonitor.isUserSelectionGesture(
            mouseDown: nil, mouseUp: .zero, clickCount: 1, shiftHeld: false))
    }
}
