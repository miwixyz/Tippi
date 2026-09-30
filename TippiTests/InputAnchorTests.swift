import XCTest
@testable import Tippi

/// AppKit coordinates: origin bottom-left, Y grows upward — "below" is a smaller Y.
final class InputAnchorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    /// Menu bar on top (25 pt), Dock at the bottom (70 pt).
    private let visible = CGRect(x: 0, y: 70, width: 1920, height: 985)
    private let panel = CGSize(width: 290, height: 340)
    private let mouse = CGPoint(x: 1800, y: 100)

    // MARK: - Placement

    func testOpensJustBelowTheSelectionLeftAligned() {
        let selection = CGRect(x: 400, y: 700, width: 120, height: 18)
        let origin = InputAnchor.origin(for: selection, panelSize: panel, visibleFrames: [visible])
        XCTAssertEqual(origin.x, 400)
        XCTAssertEqual(origin.y, selection.minY - InputAnchor.gap - panel.height)
    }

    func testFlipsAboveTheAnchorTopEdgeAtTheBottomOfTheScreen() {
        let selection = CGRect(x: 400, y: 150, width: 120, height: 18)
        let origin = InputAnchor.origin(for: selection, panelSize: panel, visibleFrames: [visible])
        XCTAssertEqual(origin.y, selection.maxY + InputAnchor.gap, "above the TOP edge, not the anchor point")
        XCTAssertGreaterThan(origin.y, selection.maxY)
    }

    func testClampsAtTheRightEdge() {
        let caret = CGRect(x: 1900, y: 700, width: 0, height: 18)
        let origin = InputAnchor.origin(for: caret, panelSize: panel, visibleFrames: [visible])
        XCTAssertEqual(origin.x, visible.maxX - InputAnchor.edgeInset - panel.width)
    }

    func testClampsAtTheLeftEdge() {
        let caret = CGRect(x: 2, y: 700, width: 0, height: 18)
        let origin = InputAnchor.origin(for: caret, panelSize: panel, visibleFrames: [visible])
        XCTAssertEqual(origin.x, visible.minX + InputAnchor.edgeInset)
    }

    func testStaysOnTheScreenHoldingTheAnchor() {
        // Second display to the left of the main one, lower and smaller.
        let left = CGRect(x: -1440, y: -200, width: 1440, height: 875)
        let selection = CGRect(x: -300, y: 500, width: 80, height: 18)
        let origin = InputAnchor.origin(for: selection, panelSize: panel, visibleFrames: [visible, left])
        let frame = CGRect(origin: origin, size: panel)
        XCTAssertTrue(left.contains(frame), "\(frame) should be inside \(left)")
        XCTAssertEqual(origin.y, selection.minY - InputAnchor.gap - panel.height)
    }

    func testAnchorInTheMenuBarStripUsesThatScreen() {
        let caret = CGRect(x: 500, y: 1060, width: 0, height: 14)
        let origin = InputAnchor.origin(for: caret, panelSize: panel, visibleFrames: [visible])
        XCTAssertTrue(visible.contains(CGRect(origin: origin, size: panel)))
    }

    // MARK: - Which anchor

    func testUsesTheFirstPlausibleCandidate() {
        let end = CGRect(x: 600, y: 500, width: 8, height: 18)
        let whole = CGRect(x: 100, y: 500, width: 500, height: 60)
        XCTAssertEqual(InputAnchor.anchor(candidates: [end, whole], mouse: mouse, screens: [screen]), end)
    }

    func testCaretWithoutWidthIsPlausible() {
        let caret = CGRect(x: 600, y: 500, width: 0, height: 18)
        XCTAssertEqual(InputAnchor.anchor(candidates: [caret], mouse: mouse, screens: [screen]), caret)
    }

    func testImplausibleBoundsFallBackToTheNextCandidateAndFinallyTheMouse() {
        let zero = CGRect.zero
        let noHeight = CGRect(x: 0, y: 1080, width: 0, height: 0)
        let offScreen = CGRect(x: 5000, y: 5000, width: 50, height: 18)
        let wholeTextView = CGRect(x: 100, y: 100, width: 900, height: 700) // > half the screen height
        let caret = CGRect(x: 300, y: 400, width: 0, height: 18)

        XCTAssertEqual(InputAnchor.anchor(candidates: [zero, noHeight, offScreen, wholeTextView, caret],
                                          mouse: mouse, screens: [screen]), caret)
        XCTAssertEqual(InputAnchor.anchor(candidates: [zero, noHeight, offScreen, wholeTextView],
                                          mouse: mouse, screens: [screen]),
                       CGRect(origin: mouse, size: .zero))
        XCTAssertEqual(InputAnchor.anchor(candidates: [], mouse: mouse, screens: [screen]),
                       CGRect(origin: mouse, size: .zero))
    }

    func testMouseFallbackStillPlacesBelowThePointer() {
        let anchor = InputAnchor.anchor(candidates: [], mouse: CGPoint(x: 500, y: 800), screens: [screen])
        let origin = InputAnchor.origin(for: anchor, panelSize: panel, visibleFrames: [visible])
        XCTAssertEqual(origin, CGPoint(x: 500, y: 800 - InputAnchor.gap - panel.height))
    }
}
