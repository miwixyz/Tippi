import XCTest
@testable import Tippi

/// Live text in the recording window (2026-10-02): the two rules that keep it
/// cheap and readable. The transcription itself is the existing Parakeet path.
final class LiveTranscriptionPreviewTests: XCTestCase {

    func testIntervalStaysAtOneSecondWhilePassesAreFast() {
        XCTAssertEqual(LiveTranscriptionPreview.nextInterval(afterPassTaking: 0.2), 1)
        XCTAssertEqual(LiveTranscriptionPreview.nextInterval(afterPassTaking: 0.5), 1)
    }

    func testIntervalStretchesWhenPassesGetSlow() {
        // Long take or weaker Mac: 0.8 s per pass → wait 1.6 s, never saturate the machine.
        XCTAssertEqual(LiveTranscriptionPreview.nextInterval(afterPassTaking: 0.8), 1.6, accuracy: 0.001)
        XCTAssertEqual(LiveTranscriptionPreview.nextInterval(afterPassTaking: 2.5), 5, accuracy: 0.001)
    }

    func testShortTextIsShownWhole() {
        XCTAssertEqual(LiveTranscriptionPreview.tail("Hallo Patrik, kurz zum CMS."), "Hallo Patrik, kurz zum CMS.")
    }

    func testLongTextShowsTheEndFromAWordBoundary() {
        let text = String(repeating: "Wort ", count: 60) + "und jetzt das Ende des Satzes."
        let t = LiveTranscriptionPreview.tail(text, maxCharacters: 40)
        XCTAssertTrue(t.hasPrefix("…"))
        XCTAssertTrue(t.hasSuffix("das Ende des Satzes."))
        XCTAssertLessThanOrEqual(t.count, 41)
        XCTAssertFalse(t.dropFirst().hasPrefix(" "), "starts at a word, not a space")
        XCTAssertTrue(text.contains(t.dropFirst()), "a real tail of the text, nothing invented")
    }

    @MainActor
    func testSettingDefaultsToOff() {
        let suite = UserDefaults(suiteName: "tippi-test-\(UUID().uuidString)")!
        let saved = DictationSettings.store
        DictationSettings.store = suite
        defer { DictationSettings.store = saved }
        XCTAssertFalse(DictationSettings.livePreviewEnabled, "off unless the user switches it on")
    }
}
