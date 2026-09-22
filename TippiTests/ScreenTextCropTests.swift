import XCTest
@testable import Tippi

/// Covers the coordinate conversion behind freeze-first screen OCR.
///
/// This is the one place in the feature that has already been wrong once. The
/// first version of screen OCR captured a **vertically mirrored** region —
/// select at the top, get the bottom. It did not surface as an error but as
/// "no text found", because there usually is nothing at the mirrored spot.
///
/// AppKit hands out screen coordinates with the origin at the **bottom** left
/// and Y growing upwards. A `CGImage` has its origin at the **top** left with Y
/// growing downwards. Every test here pins one aspect of that flip, plus the
/// point-to-pixel scaling, so the conversion can be checked without a screen,
/// without a capture and without the screen-recording permission.
final class ScreenTextCropTests: XCTestCase {

    /// Main display, 1000×800 points, Retina.
    private let main = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let mainPixels = CGSize(width: 2000, height: 1600)

    // MARK: - The flip

    /// A selection hugging the TOP of the screen must crop at y = 0.
    func testSelectionAtTopCropsAtImageOrigin() {
        let selection = CGRect(x: 0, y: 700, width: 100, height: 100)   // top 100 pt

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: main,
                                              imagePixelSize: mainPixels)

        XCTAssertEqual(crop.minY, 0, "top of the screen is y=0 in the image")
        XCTAssertEqual(crop.minX, 0)
        XCTAssertEqual(crop.width, 200)   // 100 pt × scale 2
        XCTAssertEqual(crop.height, 200)
    }

    /// A selection hugging the BOTTOM must crop at the bottom of the image.
    /// This is the assertion the mirrored version would have failed.
    func testSelectionAtBottomCropsAtImageBottom() {
        let selection = CGRect(x: 0, y: 0, width: 100, height: 100)     // bottom 100 pt

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: main,
                                              imagePixelSize: mainPixels)

        // 800 pt screen − 100 pt selection top edge = 700 pt from the top → 1400 px
        XCTAssertEqual(crop.minY, 1400)
        XCTAssertEqual(crop.maxY, 1600, "bottom edge must land on the image bottom")
    }

    /// A full-screen selection must map to the whole image — no off-by-one,
    /// no lost row, no overflow.
    func testFullScreenSelectionCoversWholeImage() {
        let crop = ScreenTextCapture.cropRect(selection: main,
                                              screenFrame: main,
                                              imagePixelSize: mainPixels)

        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 2000, height: 1600))
    }

    // MARK: - Scaling

    func testNonRetinaScreenScalesOneToOne() {
        let pixels = CGSize(width: 1000, height: 800)
        let selection = CGRect(x: 250, y: 300, width: 100, height: 200)

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: main,
                                              imagePixelSize: pixels)

        XCTAssertEqual(crop, CGRect(x: 250, y: 300, width: 100, height: 200))
        // 800 − (300+200) = 300 from the top. Same number by coincidence of the
        // fixture; asserted explicitly so a changed fixture cannot hide a bug.
        XCTAssertEqual(crop.minY, 300)
    }

    /// Non-square pixel scaling must not be collapsed into one factor.
    func testWidthAndHeightScaleIndependently() {
        let pixels = CGSize(width: 2000, height: 800)   // 2× wide, 1× tall
        let selection = CGRect(x: 100, y: 0, width: 100, height: 100)

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: main,
                                              imagePixelSize: pixels)

        XCTAssertEqual(crop.minX, 200, "x uses the horizontal factor")
        XCTAssertEqual(crop.width, 200)
        XCTAssertEqual(crop.height, 100, "y uses the vertical factor")
    }

    // MARK: - Second display

    /// A display to the right of the main one has a non-zero origin. The crop
    /// must be relative to THAT display, not to the global origin — otherwise
    /// every selection on a second screen lands outside the image.
    func testSecondDisplayToTheRightIsRelativeToItsOwnOrigin() {
        let second = CGRect(x: 1000, y: 0, width: 1920, height: 1080)
        let pixels = CGSize(width: 1920, height: 1080)
        let selection = CGRect(x: 1000, y: 980, width: 100, height: 100)  // its top-left

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: second,
                                              imagePixelSize: pixels)

        XCTAssertEqual(crop.minX, 0, "x is relative to the display, not the desktop")
        XCTAssertEqual(crop.minY, 0, "and so is y, after the flip")
    }

    /// A display ABOVE the main one has a positive Y origin in AppKit. The flip
    /// must use that display's own maxY.
    func testDisplayAboveMainUsesItsOwnMaxY() {
        let above = CGRect(x: 0, y: 800, width: 1000, height: 600)
        let pixels = CGSize(width: 1000, height: 600)
        let selection = CGRect(x: 0, y: 1300, width: 50, height: 100)     // its top edge

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: above,
                                              imagePixelSize: pixels)

        XCTAssertEqual(crop.minY, 0)
    }

    // MARK: - Degenerate input

    /// A zero-sized screen frame must not divide by zero.
    func testZeroSizedScreenFrameReturnsZeroRect() {
        let crop = ScreenTextCapture.cropRect(selection: CGRect(x: 0, y: 0, width: 10, height: 10),
                                              screenFrame: .zero,
                                              imagePixelSize: mainPixels)

        XCTAssertEqual(crop, .zero)
    }

    /// A hairline selection must still produce at least one pixel — a zero-width
    /// crop makes `CGImage.cropping(to:)` return nil, which would surface as
    /// "capture failed" instead of "nothing selected".
    func testHairlineSelectionKeepsAtLeastOnePixel() {
        let selection = CGRect(x: 10, y: 10, width: 0.2, height: 0.2)

        let crop = ScreenTextCapture.cropRect(selection: selection,
                                              screenFrame: main,
                                              imagePixelSize: mainPixels)

        XCTAssertGreaterThanOrEqual(crop.width, 1)
        XCTAssertGreaterThanOrEqual(crop.height, 1)
    }

    // MARK: - Display selection

    func testScreenForSelectionPicksTheIntersectingDisplay() throws {
        let left = ScreenTextCapture.FrozenScreen(frame: main, image: try Self.dummyImage())
        let right = ScreenTextCapture.FrozenScreen(
            frame: CGRect(x: 1000, y: 0, width: 1920, height: 1080),
            image: try Self.dummyImage()
        )

        let onRight = CGRect(x: 1500, y: 100, width: 50, height: 50)
        let picked = ScreenTextCapture.screen(for: onRight, in: [left, right])

        XCTAssertEqual(picked?.frame, right.frame)
    }

    /// A selection that intersects nothing (stale coordinates after a display
    /// was unplugged) must fall back rather than throw the user out.
    func testScreenForSelectionFallsBackWhenNothingIntersects() throws {
        let left = ScreenTextCapture.FrozenScreen(frame: main, image: try Self.dummyImage())
        let nowhere = CGRect(x: 9_000, y: 9_000, width: 10, height: 10)

        XCTAssertEqual(ScreenTextCapture.screen(for: nowhere, in: [left])?.frame, main)
    }

    private static func dummyImage() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(ctx.makeImage())
    }
}
