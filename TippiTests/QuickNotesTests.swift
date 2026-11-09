import XCTest
@testable import Tippi

/// Schnellnotizen in der Menüleiste (2026-11-09) — only the pure logic; the
/// real `NSUbiquitousKeyValueStore` is never touched here.
final class QuickNotesTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    func testMarkingAppendsInOrder() {
        let all: Set = [a, b, c]
        let one = NotesPreferences.toggledQuickNotes([], toggling: b, existing: all)
        XCTAssertEqual(one, [b])
        XCTAssertEqual(NotesPreferences.toggledQuickNotes([b], toggling: a, existing: all), [b, a])
    }

    func testUnmarkingRemoves() {
        XCTAssertEqual(NotesPreferences.toggledQuickNotes([a, b, c], toggling: b, existing: [a, b, c]), [a, c])
    }

    func testFourthNoteIsRefused() {
        XCTAssertNil(NotesPreferences.toggledQuickNotes([a, b, c], toggling: d, existing: [a, b, c, d]))
    }

    func testDeletedNoteFreesItsSlot() {
        // c was deleted — marking d must work, and c is dropped for good.
        XCTAssertEqual(NotesPreferences.toggledQuickNotes([a, b, c], toggling: d, existing: [a, b, d]), [a, b, d])
    }

    func testParseDropsGarbageAndDuplicatesAndCaps() {
        let raw = [a.uuidString, "kaputt", a.uuidString, b.uuidString, c.uuidString, d.uuidString]
        XCTAssertEqual(NotesPreferences.parseQuickNoteIDs(from: raw), [a, b, c])
    }

    func testResolveKeepsTabOrderAndSkipsMissing() {
        let notes = [Note(id: a, content: "A"), Note(id: c, content: "C")]
        XCTAssertEqual(NotesPreferences.quickNotes(ids: [c, b, a], in: notes).map(\.id), [c, a])
    }

    func testPopoverSizeIsClamped() {
        XCTAssertEqual(NotesPreferences.clampedQuickNotesSize(CGSize(width: 100, height: 5000)),
                       CGSize(width: 360, height: 900))
        XCTAssertEqual(NotesPreferences.clampedQuickNotesSize(CGSize(width: 600, height: 500)),
                       CGSize(width: 600, height: 500))
    }

    func testTabTitleIsShortened() {
        XCTAssertEqual(QuickNotesView.tabTitle("Einkauf"), "Einkauf")
        let long = QuickNotesView.tabTitle("Telefonnummern Handwerker Haus")
        XCTAssertLessThanOrEqual(long.count, 16)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
