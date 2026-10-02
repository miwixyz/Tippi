import AppKit
import XCTest
@testable import Tippi

/// Recording pill + live text in six places (Michael 2026-10-02).
final class IndicatorPositionTests: XCTestCase {
    /// A 1440×900 screen whose visible area starts above a 25 pt Dock.
    private let visible = NSRect(x: 0, y: 25, width: 1440, height: 850)
    private let size = NSSize(width: 480, height: 150)

    private func origin(_ p: DictationSettings.IndicatorPosition) -> NSPoint {
        RecordingIndicatorWindowController.origin(for: p, size: size, in: visible)
    }

    func testCentredPositionsMatchTheOldBehaviour() {
        XCTAssertEqual(origin(.bottom), NSPoint(x: 480, y: 105), "bottom centre, 80 pt above the Dock")
        XCTAssertEqual(origin(.top), NSPoint(x: 480, y: 25 + 850 - 150 - 80))
    }

    func testCornersKeep24PointsFromTheSides() {
        XCTAssertEqual(origin(.bottomLeft).x, 24)
        XCTAssertEqual(origin(.topLeft).x, 24)
        XCTAssertEqual(origin(.bottomRight).x, 1440 - 480 - 24)
        XCTAssertEqual(origin(.topRight).x, 1440 - 480 - 24)
        XCTAssertEqual(origin(.bottomLeft).y, origin(.bottom).y)
        XCTAssertEqual(origin(.topRight).y, origin(.top).y)
    }

    func testWindowStaysOnScreenEverywhere() {
        for p in DictationSettings.IndicatorPosition.allCases {
            let frame = NSRect(origin: origin(p), size: size)
            XCTAssertTrue(visible.contains(frame), "\(p) leaves the visible area")
        }
    }

    func testSettingsSavedBeforeTheChangeCarryOver() {
        XCTAssertEqual(DictationSettings.IndicatorPosition(rawValue: "bottom"), .bottom)
        XCTAssertEqual(DictationSettings.IndicatorPosition(rawValue: "top"), .top)
        XCTAssertEqual(DictationSettings.IndicatorPosition.allCases.count, 6)
    }

    func testAlignmentPutsPillAndTextIntoTheChosenCorner() {
        XCTAssertEqual(DictationSettings.IndicatorPosition.topLeft.alignment, .topLeading)
        XCTAssertEqual(DictationSettings.IndicatorPosition.bottomRight.alignment, .bottomTrailing)
        XCTAssertEqual(DictationSettings.IndicatorPosition.bottom.alignment, .bottom)
    }
}
