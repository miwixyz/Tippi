import XCTest
@testable import Tippi

/// Espanso's `$|$` cursor hint. Reported 2026-09-10: expanding `:verl` typed
/// "…Kinoauswertung von: $|$" literally into the search field, because Tippi
/// read Espanso's match files but not Espanso's marker.
final class SnippetCursorHintTests: XCTestCase {

    /// The exact snippet from the report.
    func testTheReportedSnippet() {
        let raw = "Was ist der deutsche Filmverleih für die Kinoauswertung von: $|$"
        let (text, offset) = SnippetCursorHint.split(raw)
        XCTAssertEqual(text, "Was ist der deutsche Filmverleih für die Kinoauswertung von: ")
        XCTAssertFalse(text.contains("$|$"), "the marker must never reach the user's text")
        XCTAssertEqual(offset, 0, "marker at the end means the caret already sits right")
    }

    /// The case the feature actually exists for: the caret lands mid-text.
    func testMarkerInTheMiddleMovesCaretBack() {
        let (text, offset) = SnippetCursorHint.split("Hallo $|$, schöne Grüße")
        XCTAssertEqual(text, "Hallo , schöne Grüße")
        XCTAssertEqual(offset, ", schöne Grüße".count)
    }

    func testMarkerAtTheStart() {
        let (text, offset) = SnippetCursorHint.split("$|$Rest")
        XCTAssertEqual(text, "Rest")
        XCTAssertEqual(offset, 4)
    }

    func testTextWithoutMarkerIsUntouched() {
        let raw = "ganz normaler Text ohne Marker"
        let (text, offset) = SnippetCursorHint.split(raw)
        XCTAssertEqual(text, raw)
        XCTAssertEqual(offset, 0)
    }

    func testEmptyString() {
        let (text, offset) = SnippetCursorHint.split("")
        XCTAssertEqual(text, "")
        XCTAssertEqual(offset, 0)
    }

    /// Only the first marker is honoured — Espanso's behaviour. A second one
    /// stays visible on purpose, so a broken snippet is noticeable rather than
    /// silently swallowed.
    func testOnlyTheFirstMarkerIsHonoured() {
        let (text, offset) = SnippetCursorHint.split("a $|$ b $|$ c")
        XCTAssertEqual(text, "a  b $|$ c")
        XCTAssertEqual(offset, " b $|$ c".count)
    }

    /// The offset drives arrow-key presses, and an arrow key moves one character
    /// — not one byte. An emoji after the marker must count as a single step.
    func testOffsetCountsCharactersNotBytes() {
        let (_, offset) = SnippetCursorHint.split("Text $|$ 🚀ä")
        // " ", "🚀", "ä" — three arrow-key steps. The emoji is one step, not two,
        // which is the whole point of counting characters instead of UTF-8 bytes.
        XCTAssertEqual(offset, 3)
    }

    /// A lone `$` or `|` is ordinary text and must survive.
    func testPartialMarkersAreNotStripped() {
        for raw in ["Preis: 5$", "a | b", "$ | $", "$|", "|$"] {
            let (text, offset) = SnippetCursorHint.split(raw)
            XCTAssertEqual(text, raw, "\(raw) must stay unchanged")
            XCTAssertEqual(offset, 0)
        }
    }
}
