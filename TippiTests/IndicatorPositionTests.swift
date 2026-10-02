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

    /// Review 2026-10-02: only Normal was checked; Extra large is the widest window.
    func testEveryTextSizeStaysOnScreenEverywhere() {
        for textSize in LiveTextSize.allCases {
            for p in DictationSettings.IndicatorPosition.allCases {
                let frame = NSRect(origin: RecordingIndicatorWindowController.origin(
                    for: p, size: textSize.windowSize, in: visible), size: textSize.windowSize)
                XCTAssertTrue(visible.contains(frame), "\(textSize) at \(p) leaves the visible area")
            }
        }
    }

    /// The window is big while recording (live text) and pill-sized while
    /// transcribing. The pill itself must not jump between the two.
    func testPillStaysPutBetweenRecordingAndTranscribing() {
        let pill = NSSize(width: 300, height: 44)
        for textSize in LiveTextSize.allCases {
            let big = textSize.windowSize
            for p in DictationSettings.IndicatorPosition.allCases {
                let small = RecordingIndicatorWindowController.origin(for: p, size: pill, in: visible)
                let win = RecordingIndicatorWindowController.origin(for: p, size: big, in: visible)
                let x: CGFloat
                switch p.horizontal {
                case .leading: x = win.x
                case .trailing: x = win.x + big.width - pill.width
                default: x = win.x + (big.width - pill.width) / 2
                }
                let y = p.isTop ? win.y + big.height - pill.height : win.y   // AppKit: y grows upwards
                XCTAssertEqual(x, small.x, accuracy: 0.5, "\(textSize) \(p): pill moves sideways")
                XCTAssertEqual(y, small.y, accuracy: 0.5, "\(textSize) \(p): pill moves up or down")
            }
        }
    }

    @MainActor
    func testUnknownStoredPositionFallsBackToBottomCentre() {
        let suite = UserDefaults(suiteName: "tippi-test-\(UUID().uuidString)")!
        let saved = DictationSettings.store
        DictationSettings.store = suite
        defer { DictationSettings.store = saved }
        XCTAssertEqual(DictationSettings.indicatorPosition, .bottom, "nothing stored")
        suite.set("middle", forKey: "dictation.indicator.position.v1")
        XCTAssertEqual(DictationSettings.indicatorPosition, .bottom, "unknown value")
    }

    func testAlignmentPutsPillAndTextIntoTheChosenCorner() {
        XCTAssertEqual(DictationSettings.IndicatorPosition.topLeft.alignment, .topLeading)
        XCTAssertEqual(DictationSettings.IndicatorPosition.bottomRight.alignment, .bottomTrailing)
        XCTAssertEqual(DictationSettings.IndicatorPosition.bottom.alignment, .bottom)
    }
}
