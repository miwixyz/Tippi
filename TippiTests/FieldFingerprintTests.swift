import XCTest
@testable import Tippi

/// Field-level focus guard (2026-10-27): the comparison that decides whether a
/// dictation is written or goes to the clipboard. Wrong "same" writes into the
/// wrong field; wrong "different" only costs a ⌘V — the tests pin both sides.
final class FieldFingerprintTests: XCTestCase {

    private func spot(_ role: String?, offset: CGPoint?, screen: CGPoint? = nil) -> FieldFingerprint {
        FieldFingerprint(role: role, offsetInWindow: offset, screenPosition: screen)
    }

    func testSameElementIsSameFieldEvenIfItMoved() {
        // A text view scrolls with its content: position changes, element doesn't.
        let start = spot("AXTextArea", offset: CGPoint(x: 10, y: 120))
        let now = spot("AXTextArea", offset: CGPoint(x: 10, y: -480))
        XCTAssertTrue(FieldFingerprint.isSameField(start, now, sameElement: true))
    }

    func testRebuiltElementAtSamePlaceIsSameField() {
        let start = spot("AXTextArea", offset: CGPoint(x: 10, y: 120))
        XCTAssertTrue(FieldFingerprint.isSameField(start, start, sameElement: false))
    }

    func testSmallShiftWithinToleranceIsSameField() {
        let start = spot("AXTextField", offset: CGPoint(x: 80, y: 60))
        let now = spot("AXTextField", offset: CGPoint(x: 80 + 3, y: 60 - FieldFingerprint.tolerance))
        XCTAssertTrue(FieldFingerprint.isSameField(start, now, sameElement: false))
    }

    func testNeighbouringFieldBelowIsAnotherField() {
        // Mail: To → Subject, one row (~22 pt) further down, same role.
        let to = spot("AXTextField", offset: CGPoint(x: 80, y: 60))
        let subject = spot("AXTextField", offset: CGPoint(x: 80, y: 82))
        XCTAssertFalse(FieldFingerprint.isSameField(to, subject, sameElement: false))
    }

    func testJustBeyondToleranceIsAnotherField() {
        let start = spot("AXTextField", offset: CGPoint(x: 80, y: 60))
        let now = spot("AXTextField", offset: CGPoint(x: 80, y: 60 + FieldFingerprint.tolerance + 1))
        XCTAssertFalse(FieldFingerprint.isSameField(start, now, sameElement: false))
    }

    func testDifferentRoleIsAnotherField() {
        // Mail body (text area) vs subject (text field), or a button that took the focus.
        let body = spot("AXTextArea", offset: CGPoint(x: 0, y: 140))
        XCTAssertFalse(FieldFingerprint.isSameField(body, spot("AXTextField", offset: CGPoint(x: 0, y: 140)),
                                                    sameElement: false))
        XCTAssertFalse(FieldFingerprint.isSameField(body, spot("AXButton", offset: CGPoint(x: 0, y: 140)),
                                                    sameElement: false))
    }

    func testWindowDraggedKeepsSameField() {
        // Screen position jumped 300 pt, the offset inside the window did not.
        let start = spot("AXTextArea", offset: CGPoint(x: 10, y: 120), screen: CGPoint(x: 210, y: 320))
        let now = spot("AXTextArea", offset: CGPoint(x: 10, y: 120), screen: CGPoint(x: 510, y: 320))
        XCTAssertTrue(FieldFingerprint.isSameField(start, now, sameElement: false))
    }

    func testScreenPositionUsedWhenWindowOffsetMissing() {
        let start = spot("AXTextField", offset: nil, screen: CGPoint(x: 200, y: 300))
        XCTAssertTrue(FieldFingerprint.isSameField(start, spot("AXTextField", offset: nil, screen: CGPoint(x: 202, y: 301)),
                                                   sameElement: false))
        XCTAssertFalse(FieldFingerprint.isSameField(start, spot("AXTextField", offset: nil, screen: CGPoint(x: 200, y: 330)),
                                                    sameElement: false))
    }

    func testNothingToCompareDoesNotBlock() {
        // App reports neither role nor position: the old behaviour (insert) stays.
        XCTAssertTrue(FieldFingerprint.isSameField(spot(nil, offset: nil), spot(nil, offset: nil), sameElement: false))
        XCTAssertTrue(FieldFingerprint.isSameField(spot("AXTextArea", offset: nil), spot("AXTextArea", offset: nil),
                                                   sameElement: false))
    }

    func testToleranceStaysBelowOneRowOfFields() {
        // The design argument in FieldFingerprint.tolerance, pinned: neighbouring
        // one-line fields are ≥ 20 pt apart, the tolerance must stay well under that.
        XCTAssertLessThan(FieldFingerprint.tolerance, 20 / 2)
        XCTAssertGreaterThanOrEqual(FieldFingerprint.tolerance, 3)
    }
}
