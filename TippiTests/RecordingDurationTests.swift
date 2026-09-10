import XCTest
@testable import Tippi

/// The stopwatch in the recording pill. Pure formatting, so it is worth pinning:
/// the pill is sized once when the window opens, and a format that changes width
/// unexpectedly makes it twitch or clip.
final class RecordingDurationTests: XCTestCase {

    func testZeroAndStart() {
        XCTAssertEqual(RecordingDuration.formatted(0), "0:00")
        XCTAssertEqual(RecordingDuration.formatted(0.4), "0:00")
        XCTAssertEqual(RecordingDuration.formatted(1), "0:01")
    }

    /// Truncation, not rounding: at 1.9 s the user has not reached 2 s yet, and a
    /// stopwatch that jumps ahead of itself reads as a bug.
    func testTruncatesRatherThanRounds() {
        XCTAssertEqual(RecordingDuration.formatted(1.9), "0:01")
        XCTAssertEqual(RecordingDuration.formatted(59.99), "0:59")
    }

    func testMinuteBoundary() {
        XCTAssertEqual(RecordingDuration.formatted(59), "0:59")
        XCTAssertEqual(RecordingDuration.formatted(60), "1:00")
        XCTAssertEqual(RecordingDuration.formatted(61), "1:01")
        XCTAssertEqual(RecordingDuration.formatted(599), "9:59")
    }

    /// The hold watchdog fires here — the pill must still read sensibly.
    func testFiveMinuteWatchdogPoint() {
        XCTAssertEqual(RecordingDuration.formatted(300), "5:00")
    }

    func testHourBoundarySwitchesFormat() {
        XCTAssertEqual(RecordingDuration.formatted(3599), "59:59")
        XCTAssertEqual(RecordingDuration.formatted(3600), "1:00:00")
        XCTAssertEqual(RecordingDuration.formatted(3661), "1:01:01")
    }

    /// Seconds and minutes are zero-padded, the leading unit is not — "0:07",
    /// never "00:07" or "0:7".
    func testPadding() {
        XCTAssertEqual(RecordingDuration.formatted(7), "0:07")
        XCTAssertEqual(RecordingDuration.formatted(607), "10:07")
        XCTAssertEqual(RecordingDuration.formatted(3607), "1:00:07")
    }

    /// Defensive: a negative or non-finite value must not produce "-1:-1" or crash
    /// on the Int conversion. `AVAudioRecorder.currentTime` returns a negative
    /// value once the recorder is stopped.
    func testNegativeAndNonFiniteAreSafe() {
        XCTAssertEqual(RecordingDuration.formatted(-5), "0:00")
        XCTAssertEqual(RecordingDuration.formatted(.infinity), "0:00")
        XCTAssertEqual(RecordingDuration.formatted(.nan), "0:00")
    }

    /// Width stability is the whole reason for monospaced digits: every string
    /// under ten minutes must have the same character count, or the pill resizes
    /// mid-recording in a window that was measured once.
    func testWidthIsStableUnderTenMinutes() {
        let lengths = Set((0..<600).map { RecordingDuration.formatted(TimeInterval($0)).count })
        XCTAssertEqual(lengths, [4], "expected every value below 10:00 to render as 4 characters")
    }
}
