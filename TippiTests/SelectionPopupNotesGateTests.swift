import AppKit
import XCTest
@testable import Tippi

/// Pins the rule that decides whether the selection bar is allowed to appear
/// while Tippi itself is frontmost.
///
/// Reported 2026-09-20: selecting text in the Notes window produced nothing.
/// `checkSelection()` already had the exception — it bypasses the app-level
/// guard for the focused Notes text view — but `scheduleCheck()` returned one
/// layer earlier on a bare `!NSApp.isActive`, so that exception was dead code.
///
/// Third instance of the same shape in a single day: a guard on an earlier
/// layer silently defeating a special case on a later one. The snippet engine
/// had it too (fixed in 2.11.4). That is why this is a test and not a comment.
final class SelectionPopupNotesGateTests: XCTestCase {

    func testAnotherAppFrontmostAlwaysProceeds() {
        XCTAssertTrue(
            SelectionPopupMonitor.shouldConsiderSelection(appIsActive: false, notesEditorHasFocus: false),
            "The ordinary case — Tippi is not frontmost, the bar is for other apps."
        )
    }

    func testNotesEditorFocusedProceedsEvenThoughTippiIsFrontmost() {
        // The reported bug, as an assertion.
        XCTAssertTrue(
            SelectionPopupMonitor.shouldConsiderSelection(appIsActive: true, notesEditorHasFocus: true),
            "Notes is an ordinary content surface; the bar is as wanted there as anywhere else."
        )
    }

    func testOtherTippiWindowsStaySuppressed() {
        // The reason the guard exists: Settings, the snippet editor, the bar
        // itself. Selecting text there must not pop a bar over Tippi's own UI.
        XCTAssertFalse(
            SelectionPopupMonitor.shouldConsiderSelection(appIsActive: true, notesEditorHasFocus: false)
        )
    }
}
