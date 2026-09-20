import AppKit
import XCTest
@testable import Tippi

/// Covers the rule that decides whether a keystroke is dropped while Tippi
/// itself is frontmost.
///
/// Background (2026-09-20): the guard used to be a bare `NSApp.isActive`, which
/// is app-wide. Its stated purpose was narrow — a trigger typed into the
/// snippet editor in Settings must not expand itself — but it also silenced the
/// Notes window, where expansion is exactly what a user expects. Nothing in the
/// UI showed a cause; the keystroke arrived and was discarded one line later.
///
/// The decision is now a pure function over the key window's identifier, which
/// is why it can be tested at all. `MainActor` because the monitor is
/// `@MainActor`-isolated; the function itself touches no window.
@MainActor
final class SnippetWindowSuppressionTests: XCTestCase {

    // MARK: - The allow-list itself

    func testNotesWindowIsAllowedToExpand() {
        XCTAssertFalse(
            SnippetKeystrokeMonitor.shouldDiscardWhileFrontmost(
                keyWindowIdentifier: "TippiNotesWindow"
            ),
            "Notes is a normal editing surface — snippets must expand there."
        )
    }

    func testSettingsWindowStaysSuppressed() {
        // The original reason the guard exists. Typing ":nl" into the snippet
        // editor defines the trigger; expanding it there would make the field
        // unusable.
        XCTAssertTrue(
            SnippetKeystrokeMonitor.shouldDiscardWhileFrontmost(
                keyWindowIdentifier: "TippiSettingsWindow"
            )
        )
    }

    func testUnidentifiedWindowIsSuppressed() {
        // Allow-list, not deny-list: a window has to declare itself. A future
        // Tippi window must not silently start expanding because nobody
        // remembered to add it to a block list.
        XCTAssertTrue(
            SnippetKeystrokeMonitor.shouldDiscardWhileFrontmost(keyWindowIdentifier: nil)
        )
        XCTAssertTrue(
            SnippetKeystrokeMonitor.shouldDiscardWhileFrontmost(
                keyWindowIdentifier: "SomeFutureTippiPanel"
            )
        )
    }

    // MARK: - The contract between the two files

    /// The identifier is a string shared across a module boundary:
    /// `NotesWindowController` stamps it onto the window, `SnippetKeystrokeMonitor`
    /// matches against it. A rename on either side compiles fine and silently
    /// restores the exact bug this change fixes — nothing would fail except the
    /// feature. This test is the only thing that notices.
    func testNotesWindowIdentifierIsOnTheAllowList() {
        XCTAssertTrue(
            SnippetKeystrokeMonitor.expansionAllowedWindowIdentifiers
                .contains(NotesWindowController.windowIdentifier.rawValue),
            """
            NotesWindowController.windowIdentifier and \
            SnippetKeystrokeMonitor.expansionAllowedWindowIdentifiers have drifted apart. \
            Snippets stopped working in the Notes window.
            """
        )
    }

    /// Guards the other direction: the allow-list must not quietly grow to
    /// include a window where a trigger is being *defined* rather than used.
    func testAllowListContainsOnlyNotes() {
        XCTAssertEqual(
            SnippetKeystrokeMonitor.expansionAllowedWindowIdentifiers,
            [NotesWindowController.windowIdentifier.rawValue],
            "Adding a window here means snippets expand while typing in it — deliberate act only."
        )
    }

    // MARK: - What this suite deliberately does NOT cover

    /// Whether `makeWindowController()` actually *calls* the stamp is not
    /// asserted here. Doing so means going through `show()`, which flips
    /// `NSApp.setActivationPolicy(.regular)`, activates the app and kicks off a
    /// `NotesStore.refresh()` against the real iCloud container. A unit test
    /// that changes the machine it runs on is worth less than the gap it closes
    /// — and the same rule already cost a round on 2026-09-14, when iCloud
    /// entitlements were stripped from a diagnostic build and made the
    /// measurement meaningless.
    ///
    /// The gap is covered by the manual smoke test instead: open Notes, type a
    /// trigger, watch it expand. One line in the release checklist, no
    /// environment damage.
    ///
    /// The contract test above is the one that matters day to day: it catches a
    /// rename, which is the realistic regression. A deleted assignment line
    /// fails the smoke test immediately.
}
