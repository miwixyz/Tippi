import CoreGraphics
import XCTest
@testable import Tippi

/// Voice/core fixes from the 2026-09-27 audit (group E).
final class VoiceCoreAuditFixTests: XCTestCase {

    // MARK: - Blank capture detection

    private func image(width: Int, height: Int, fill: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        for y in 0..<height { for x in 0..<width {
            let (r, g, b) = fill(x, y)
            ctx.setFillColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        } }
        return try XCTUnwrap(ctx.makeImage())
    }

    /// Opaque black BGRA — the "permission missing" capture. The raw-byte
    /// sampler read the alpha byte as colour and missed it (measured).
    func testOpaqueBlackCaptureIsBlank() throws {
        for (w, h) in [(301, 97), (1440, 90), (57, 33)] {
            XCTAssertTrue(ScreenTextCapture.isBlank(try image(width: w, height: h) { _, _ in (0, 0, 0) }), "\(w)x\(h)")
        }
    }

    func testCaptureWithTextIsNotBlank() throws {
        let img = try image(width: 200, height: 60) { x, y in (y > 25 && y < 32 && x % 6 < 3) ? (0, 0, 0) : (255, 255, 255) }
        XCTAssertFalse(ScreenTextCapture.isBlank(img))
    }

    // MARK: - Left vs right modifier

    func testReleasingRightShiftWhileLeftIsHeldReadsReleased() {
        let leftHeld = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x0002)
        XCTAssertFalse(HotkeyManager.isModifierPressed(.rightShift, flags: leftHeld))
        XCTAssertTrue(HotkeyManager.isModifierPressed(.leftShift, flags: leftHeld))
    }

    func testRightOptionPressed() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x0040)
        XCTAssertTrue(HotkeyManager.isModifierPressed(.rightOption, flags: flags))
        XCTAssertFalse(HotkeyManager.isModifierPressed(.leftOption, flags: flags))
    }

    /// Events without device bits (virtual keyboards) fall back to the generic flag.
    func testNoDeviceBitsFallsBackToGenericFlag() {
        XCTAssertTrue(HotkeyManager.isModifierPressed(.rightShift, flags: .maskShift))
        XCTAssertFalse(HotkeyManager.isModifierPressed(.rightShift, flags: []))
    }

    // MARK: - whisper-cli error text

    func testWhisperErrorIsTheTailNotTheInitLog() {
        let stderr = """
        whisper_init_from_file_with_params_no_state: loading model from '/Users/x/model.bin'
        whisper_model_load: n_vocab = 51865
        error: failed to read WAV file 'x.wav'
        """
        let message = WhisperStderr.lastLines(of: stderr, fallback: "exit 2")
        XCTAssertTrue(message.hasSuffix("error: failed to read WAV file 'x.wav'"), message)
        XCTAssertEqual(WhisperStderr.lastLines(of: "  \n", fallback: "exit 2"), "exit 2")
    }

    /// A big, uniformly light sample (little text the point samples missed)
    /// must go to Vision, not claim "permission missing" (review 2026-09-27).
    func testUniformLightCaptureIsNotBlank() throws {
        XCTAssertFalse(ScreenTextCapture.isBlank(try image(width: 400, height: 300) { _, _ in (250, 250, 250) }))
    }
}
