import XCTest
@testable import Tippi

final class SelectionPopupPositionerTests: XCTestCase {
    // A selection comfortably in the middle of a 1920x1080 screen — no
    // clamping should kick in for any of these.
    private let selection = CGRect(x: 800, y: 500, width: 100, height: 20)
    private let popupSize = CGSize(width: 200, height: 40)
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testBelowIsVisuallyLowerOnScreen() {
        // AppKit Y grows upward, so "below" means a SMALLER Y than the
        // selection's own Y — this is the exact sign-confusion this
        // feature's coordinate math is most likely to get backwards.
        let origin = SelectionPopupPositioner.origin(for: selection, popupSize: popupSize, position: .below, screenFrame: screen)
        XCTAssertLessThan(origin.y, selection.minY)
        XCTAssertEqual(origin.x, selection.midX - popupSize.width / 2)
    }

    func testAboveIsVisuallyHigherOnScreen() {
        let origin = SelectionPopupPositioner.origin(for: selection, popupSize: popupSize, position: .above, screenFrame: screen)
        XCTAssertGreaterThan(origin.y, selection.maxY)
    }

    func testRightIsToTheRightOfSelection() {
        let origin = SelectionPopupPositioner.origin(for: selection, popupSize: popupSize, position: .right, screenFrame: screen)
        XCTAssertGreaterThan(origin.x, selection.maxX)
    }

    func testLeftIsToTheLeftOfSelection() {
        let origin = SelectionPopupPositioner.origin(for: selection, popupSize: popupSize, position: .left, screenFrame: screen)
        XCTAssertLessThan(origin.x, selection.minX)
        XCTAssertEqual(origin.x, selection.minX - SelectionPopupPositioner.gap - popupSize.width)
    }

    func testClampsAgainstRightScreenEdge() {
        let nearEdgeSelection = CGRect(x: 1900, y: 500, width: 15, height: 20)
        let origin = SelectionPopupPositioner.origin(for: nearEdgeSelection, popupSize: popupSize, position: .right, screenFrame: screen)
        XCTAssertLessThanOrEqual(origin.x + popupSize.width, screen.maxX)
    }

    func testClampsAgainstLeftScreenEdge() {
        let nearEdgeSelection = CGRect(x: 5, y: 500, width: 15, height: 20)
        let origin = SelectionPopupPositioner.origin(for: nearEdgeSelection, popupSize: popupSize, position: .left, screenFrame: screen)
        XCTAssertGreaterThanOrEqual(origin.x, screen.minX)
    }

    func testClampsAgainstTopScreenEdge() {
        let nearTopSelection = CGRect(x: 800, y: 1060, width: 100, height: 15)
        let origin = SelectionPopupPositioner.origin(for: nearTopSelection, popupSize: popupSize, position: .above, screenFrame: screen)
        XCTAssertLessThanOrEqual(origin.y + popupSize.height, screen.maxY)
    }

    func testClampsAgainstBottomScreenEdge() {
        let nearBottomSelection = CGRect(x: 800, y: 5, width: 100, height: 15)
        let origin = SelectionPopupPositioner.origin(for: nearBottomSelection, popupSize: popupSize, position: .below, screenFrame: screen)
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
    }

    // MARK: - Auto-flip (regression: 2026-09-09 real-world report)
    //
    // A selection near the top of the screen with position=.above used to
    // just get clamped back down — landing the bar on top of/overlapping
    // the selected line instead of clearly above it. It must now flip to
    // .below instead, the same way a tooltip or popover would.

    func testFlipsToBelowWhenAboveDoesNotFit() {
        let nearTopSelection = CGRect(x: 800, y: 1060, width: 100, height: 15)
        let origin = SelectionPopupPositioner.origin(for: nearTopSelection, popupSize: popupSize, position: .above, screenFrame: screen)
        // Genuinely below the selection now, not merely clamped near the top.
        XCTAssertLessThan(origin.y + popupSize.height, nearTopSelection.minY)
    }

    func testFlipsToAboveWhenBelowDoesNotFit() {
        let nearBottomSelection = CGRect(x: 800, y: 5, width: 100, height: 15)
        let origin = SelectionPopupPositioner.origin(for: nearBottomSelection, popupSize: popupSize, position: .below, screenFrame: screen)
        XCTAssertGreaterThan(origin.y, nearBottomSelection.maxY)
    }

    func testFlipsToLeftWhenRightDoesNotFit() {
        let nearRightSelection = CGRect(x: 1900, y: 500, width: 15, height: 20)
        let origin = SelectionPopupPositioner.origin(for: nearRightSelection, popupSize: popupSize, position: .right, screenFrame: screen)
        XCTAssertLessThan(origin.x + popupSize.width, nearRightSelection.minX)
    }

    func testFlipsToRightWhenLeftDoesNotFit() {
        let nearLeftSelection = CGRect(x: 5, y: 500, width: 15, height: 20)
        let origin = SelectionPopupPositioner.origin(for: nearLeftSelection, popupSize: popupSize, position: .left, screenFrame: screen)
        XCTAssertGreaterThan(origin.x, nearLeftSelection.maxX)
    }

    /// Neither side fits (a popup wider than the whole screen) — must still
    /// return *something* on-screen rather than crashing or going negative.
    func testFallsBackToClampingWhenNeitherSideFits() {
        let tinyScreen = CGRect(x: 0, y: 0, width: 250, height: 250)
        let centeredSelection = CGRect(x: 100, y: 120, width: 20, height: 15)
        let origin = SelectionPopupPositioner.origin(for: centeredSelection, popupSize: popupSize, position: .above, screenFrame: tinyScreen)
        XCTAssertGreaterThanOrEqual(origin.x, tinyScreen.minX)
        XCTAssertLessThanOrEqual(origin.x + popupSize.width, tinyScreen.maxX)
        XCTAssertGreaterThanOrEqual(origin.y, tinyScreen.minY)
        XCTAssertLessThanOrEqual(origin.y + popupSize.height, tinyScreen.maxY)
    }

    // MARK: - Dismiss when the pointer moves away

    private let bar = CGRect(x: 750, y: 440, width: 200, height: 40) // below `selection`

    func testPointerOnBarOrSelectionHasNotLeft() {
        XCTAssertFalse(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: 850, y: 460), popupFrame: bar, selectionBounds: selection))
        XCTAssertFalse(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: 850, y: 510), popupFrame: bar, selectionBounds: selection))
    }

    func testPointerJustInsideTheMarginHasNotLeft() {
        // 99pt right of the zone's right edge — the bar (950) is wider than the selection (900)
        XCTAssertFalse(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: bar.maxX + 99, y: 510), popupFrame: bar, selectionBounds: selection))
    }

    func testPointerFarAwayHasLeft() {
        XCTAssertTrue(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: bar.maxX + 101, y: 510), popupFrame: bar, selectionBounds: selection))
        // menu bar, top left
        XCTAssertTrue(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: 20, y: 1060), popupFrame: bar, selectionBounds: selection))
    }

    func testEndOfLongSelectionFarFromCentredBarHasNotLeft() {
        // The reason the zone includes the selection: a 900pt-wide line, bar
        // centred on it, pointer resting where the drag ended — 350pt from the
        // bar's edge, yet the bar must stay reachable.
        let longLine = CGRect(x: 100, y: 500, width: 900, height: 20)
        let centredBar = CGRect(x: 450, y: 440, width: 200, height: 40)
        XCTAssertFalse(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: 1000, y: 505), popupFrame: centredBar, selectionBounds: longLine))
    }

    func testZeroSizeFallbackAnchorStillCountsAsInsideTheZone() {
        // No usable AX bounds → anchor is the mouse position as a zero-size rect.
        let mousePoint = CGRect(x: 1500, y: 800, width: 0, height: 0)
        let barNearMouse = CGRect(x: 1400, y: 740, width: 200, height: 40)
        XCTAssertFalse(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: 1500, y: 800), popupFrame: barNearMouse, selectionBounds: mousePoint))
        XCTAssertFalse(SelectionPopupPositioner.pointerHasLeft(CGPoint(x: 1500, y: 895), popupFrame: barNearMouse, selectionBounds: mousePoint))
    }

    // MARK: - Re-showing a dismissed selection

    func testMouseUpOnTheSelectionCountsAsOnIt() {
        XCTAssertTrue(SelectionPopupPositioner.pointerIsOnSelection(CGPoint(x: 850, y: 510), selectionBounds: selection))
        // right at the glyph edge, within the 4pt slack
        XCTAssertTrue(SelectionPopupPositioner.pointerIsOnSelection(CGPoint(x: selection.maxX + 3, y: 510), selectionBounds: selection))
    }

    func testClickNextToOrFarFromTheSelectionIsNotOnIt() {
        // The 2026-09-24 case: a click elsewhere that leaves the selection intact
        XCTAssertFalse(SelectionPopupPositioner.pointerIsOnSelection(CGPoint(x: selection.maxX + 30, y: 510), selectionBounds: selection))
        XCTAssertFalse(SelectionPopupPositioner.pointerIsOnSelection(CGPoint(x: 20, y: 1060), selectionBounds: selection))
        // on the bar is not on the selection either
        XCTAssertFalse(SelectionPopupPositioner.pointerIsOnSelection(CGPoint(x: 850, y: 460), selectionBounds: selection))
    }
}
