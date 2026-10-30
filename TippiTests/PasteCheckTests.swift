import XCTest
@testable import Tippi

/// The decision behind the clipboard fallback since 2026-10-30 (Apple Mail:
/// ⌘V sometimes went nowhere). Only `.notLanded` keeps the result on the
/// clipboard instead of restoring the old one — so it must need proof: a
/// readable value before and after, and no change.
final class PasteCheckTests: XCTestCase {
    func testChangedValueMeansLanded() {
        XCTAssertEqual(TextInsertion.pasteOutcome(before: "Hallo", after: "Hallo Welt"), .landed)
    }

    func testUnchangedValueMeansNotLanded() {
        XCTAssertEqual(TextInsertion.pasteOutcome(before: "Hallo", after: "Hallo"), .notLanded)
    }

    func testUnreadableBeforeIsUnknown() {
        XCTAssertEqual(TextInsertion.pasteOutcome(before: nil, after: "Hallo"), .unknown)
    }

    func testUnreadableAfterIsUnknown() {
        XCTAssertEqual(TextInsertion.pasteOutcome(before: "Hallo", after: nil), .unknown)
    }

    /// An empty field that stays empty is still proof — the paste added nothing.
    func testEmptyFieldStayingEmptyIsNotLanded() {
        XCTAssertEqual(TextInsertion.pasteOutcome(before: "", after: ""), .notLanded)
    }

    func testNoPidGivesNoTargetAndNoWait() async {
        let target = await TextInsertion.preparePasteTarget(pid: nil)
        XCTAssertNil(target.element)
        XCTAssertNil(target.valueBefore)
        XCTAssertEqual(target.focusWaitMs, 0)
    }
}
