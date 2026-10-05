import XCTest
@testable import Tippi

/// Lists in the Notes editor (2026-10-05): Return continues, toolbar toggles,
/// click on the box checks it. Pure string logic — the text view only calls it.
final class NoteListEditingTests: XCTestCase {

    typealias Lists = NoteListEditing

    // MARK: - Parsing

    func testRecognisesAllThreeKinds() {
        XCTAssertEqual(Lists.parse("- Milch")?.kind, .bullet)
        XCTAssertEqual(Lists.parse("• Milch")?.kind, .bullet)
        XCTAssertEqual(Lists.parse("- [ ] Milch")?.kind, .checklist)
        XCTAssertEqual(Lists.parse("- [x] Milch")?.checked, true)
        XCTAssertEqual(Lists.parse("3. Milch")?.number, 3)
        XCTAssertEqual(Lists.parse("3) Milch")?.kind, .numbered)
    }

    func testPlainTextIsNoList() {
        XCTAssertNil(Lists.parse("Milch"))
        XCTAssertNil(Lists.parse("-Milch"))          // no space after dash
        XCTAssertNil(Lists.parse("12345. Zeile"))    // more than 4 digits: a number, not a list
        XCTAssertNil(Lists.parse("3.5 Liter"))
    }

    func testIndentIsPartOfThePrefix() {
        let item = Lists.parse("    - [ ] Brot")
        XCTAssertEqual(item?.indent, "    ")
        XCTAssertEqual(item?.prefix, "    - [ ] ")
        XCTAssertEqual(item?.content, "Brot")
    }

    // MARK: - Return

    func testReturnContinuesEachKind() {
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "- Milch"), .continueWith("- "))
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "  * Milch"), .continueWith("  * "))
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "- [x] Milch"), .continueWith("- [ ] "),
                       "a new checklist item starts unchecked")
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "9. Milch"), .continueWith("10. "))
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "2) Milch"), .continueWith("3) "))
    }

    func testReturnOnEmptyItemEndsTheList() {
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "- "), .endList(prefixLength: 2))
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "  - [ ] "), .endList(prefixLength: 8))
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "4. "), .endList(prefixLength: 3))
    }

    func testReturnOnPlainLineDoesNothingSpecial() {
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: "Einkauf"), .none)
        XCTAssertEqual(Lists.continuation(forLineBeforeCursor: ""), .none)
    }

    // MARK: - Toolbar toggle

    func testToggleMakesAListAndKeepsEmptyLines() {
        XCTAssertEqual(Lists.toggle(.bullet, lines: ["Milch", "", "Brot"]), ["- Milch", "", "- Brot"])
        XCTAssertEqual(Lists.toggle(.checklist, lines: ["Milch", "Brot"]), ["- [ ] Milch", "- [ ] Brot"])
        XCTAssertEqual(Lists.toggle(.numbered, lines: ["Milch", "", "Brot"]), ["1. Milch", "", "2. Brot"])
    }

    func testSecondToggleRemovesTheList() {
        XCTAssertEqual(Lists.toggle(.bullet, lines: ["- Milch", "  - Brot"]), ["Milch", "  Brot"])
        XCTAssertEqual(Lists.toggle(.checklist, lines: ["- [x] Milch", "- [ ] Brot"]), ["Milch", "Brot"])
        XCTAssertEqual(Lists.toggle(.numbered, lines: ["1. Milch", "2. Brot"]), ["Milch", "Brot"])
    }

    func testToggleConvertsOtherKindsWithoutDoublePrefix() {
        XCTAssertEqual(Lists.toggle(.numbered, lines: ["- Milch", "- [x] Brot"]), ["1. Milch", "2. Brot"])
        XCTAssertEqual(Lists.toggle(.checklist, lines: ["- Milch", "- [x] Brot"]), ["- [ ] Milch", "- [x] Brot"],
                       "an item that was already checked stays checked")
        XCTAssertEqual(Lists.toggle(.bullet, lines: ["- Milch", "Brot"]), ["- Milch", "- Brot"],
                       "mixed selection → make all bullets, don't remove")
    }

    func testToggleOnEmptyLineStartsAList() {
        XCTAssertEqual(Lists.toggle(.bullet, lines: [""]), ["- "])
        XCTAssertEqual(Lists.toggle(.checklist, lines: ["  "]), ["  - [ ] "])
        XCTAssertEqual(Lists.toggle(.numbered, lines: [""]), ["1. "])
    }

    // MARK: - Checkbox

    func testCheckboxRangeAndToggle() {
        XCTAssertEqual(Lists.checkboxRange(in: "- [ ] Milch"), NSRange(location: 2, length: 3))
        XCTAssertEqual(Lists.checkboxRange(in: "\t- [x] Milch"), NSRange(location: 3, length: 3))
        XCTAssertNil(Lists.checkboxRange(in: "- Milch"))
        XCTAssertEqual(Lists.toggledCheckbox(in: "- [ ] Milch"), "[x]")
        XCTAssertEqual(Lists.toggledCheckbox(in: "- [X] Milch"), "[ ]")
        XCTAssertNil(Lists.toggledCheckbox(in: "Milch"))
    }
}
