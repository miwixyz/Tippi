import AppKit
import XCTest
@testable import Tippi

/// The wiring in `PasteAwareTextView` (Return, toolbar) on a real NSTextView —
/// the pure logic is covered in `NoteListEditingTests`.
@MainActor
final class NoteListTextViewTests: XCTestCase {

    private func makeView(_ text: String, cursor: Int) -> PlainTextEditor.PasteAwareTextView {
        let view = PlainTextEditor.PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isRichText = false
        view.allowsUndo = true
        view.string = text
        view.setSelectedRange(NSRange(location: cursor, length: 0))
        return view
    }

    func testReturnContinuesAndEndsAList() {
        let view = makeView("- Milch", cursor: 7)
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "- Milch\n- ")
        view.insertNewline(nil)                       // empty item → list ends
        XCTAssertEqual(view.string, "- Milch\n")
        XCTAssertEqual(view.selectedRange().location, 8)
    }

    func testReturnContinuesNumbersAndUncheckedBoxes() {
        let numbered = makeView("1. Eins", cursor: 7)
        numbered.insertNewline(nil)
        XCTAssertEqual(numbered.string, "1. Eins\n2. ")

        let checklist = makeView("- [x] Erledigt", cursor: 14)
        checklist.insertNewline(nil)
        XCTAssertEqual(checklist.string, "- [x] Erledigt\n- [ ] ")
    }

    func testReturnOnPlainTextIsUnchanged() {
        let view = makeView("Einkauf", cursor: 7)
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "Einkauf\n")
    }

    func testToolbarTogglesSelectedLines() {
        let view = makeView("Milch\nBrot\nRest", cursor: 0)
        view.setSelectedRange(NSRange(location: 0, length: 10))   // "Milch\nBrot"
        view.applyList(.checklist)
        XCTAssertEqual(view.string, "- [ ] Milch\n- [ ] Brot\nRest")
        view.applyList(.checklist)                                // second press: plain again
        XCTAssertEqual(view.string, "Milch\nBrot\nRest")
    }
}
