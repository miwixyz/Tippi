import AppKit
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

    // MARK: Text size (Michael 2026-10-02: „Schrift ein bisschen klein“)

    func testTextSizesGrow() {
        let sizes = LiveTextSize.allCases
        XCTAssertEqual(sizes, [.normal, .large, .extraLarge])
        for (a, b) in zip(sizes, sizes.dropFirst()) {
            XCTAssertLessThan(a.pointSize, b.pointSize)
            XCTAssertLessThan(a.windowSize.width, b.windowSize.width)
            XCTAssertLessThan(a.windowSize.height, b.windowSize.height)
        }
    }

    @MainActor
    func testTextSizeDefaultsToNormalAndSurvivesUnknownValues() {
        let suite = UserDefaults(suiteName: "tippi-test-\(UUID().uuidString)")!
        let saved = DictationSettings.store
        DictationSettings.store = suite
        defer { DictationSettings.store = saved }
        XCTAssertEqual(DictationSettings.liveTextSize, .normal)
        suite.set("huge", forKey: "dictation.livePreview.textSize.v1")
        XCTAssertEqual(DictationSettings.liveTextSize, .normal)
    }

    /// Measured, not estimated: every tail of a real German dictation must fit
    /// the three lines the window shows (`lineLimit(3)`), at the real text width
    /// (`frame(maxWidth: width - 40)`, padding outside), with real line heights.
    /// Review 2026-10-02: the first version allowed 4 lines, measured a narrower
    /// width and counted glyph boxes — so it could never fail.
    func testEveryTailFitsThreeLinesAtEverySize() {
        let sample = "Hallo Patrik, ich habe mir gerade die neue Version des CMS angesehen. Die Navigation "
            + "gefällt mir deutlich besser als vorher, aber beim Hochladen der Filmplakate gibt es noch ein Problem, "
            + "wenn ein Bild größer als fünf Megabyte ist, erscheint keine Fehlermeldung. Außerdem würde ich gern "
            + "wissen, ob wir die Spielzeiten für Donnerstag schon übernehmen können oder ob das Kino Weißenburg "
            + "noch Änderungen schickt. Bitte gib mir bis morgen Mittag kurz Bescheid, danke dir."
        for size in LiveTextSize.allCases {
            let font = NSFont(name: FamilyTheme.fontFamily, size: size.pointSize) ?? .systemFont(ofSize: size.pointSize)
            XCTAssertEqual(font.familyName, FamilyTheme.fontFamily, "measured with Tippi's real font, not a fallback")
            let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
            let width = size.windowSize.width - 40
            var worst = 0
            for end in stride(from: 40, through: sample.count, by: 7) {
                let text = LiveTranscriptionPreview.tail(String(sample.prefix(end)), maxCharacters: size.tailCharacters)
                let rect = (text as NSString).boundingRect(
                    with: NSSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: [.font: font])
                worst = max(worst, Int((rect.height / lineHeight).rounded()))
            }
            XCTAssertLessThanOrEqual(worst, 3, "\(size): a tail needs \(worst) lines")
            // Three lines plus pill (~44), spacing 8 and box padding 20 fit the window.
            XCTAssertLessThanOrEqual(3 * lineHeight + 44 + 8 + 20, size.windowSize.height, "\(size): window too low")
        }
    }
}
