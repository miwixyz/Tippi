import AppKit
import ApplicationServices
import XCTest
@testable import Tippi

/// Covers the single decision "where does a replacement go", which used to be
/// copy-pasted into three call sites in `AppDelegate` and produced the same
/// bug twice (v2.8.3 `a3c45ce`, audit 2026-09-19 `3532ca0`): a result meant
/// for Tippi's own Notes editor written into whatever app was in front.
///
/// The three call sites each build a `ReplacementTarget` and hand it to
/// `ReplacementWriter` — so the case that matters, "native capture present ⇒
/// `.native`", is exercised here once per call-site shape. `AppDelegate`
/// itself is not instantiated: its stored properties start Carbon hot keys,
/// the audio recorder and several panels.
final class ReplacementTargetTests: XCTestCase {

    // MARK: - Call site 1: selection action bar (SelectionSnapshot)

    /// A selection inside Tippi's own Notes editor must resolve to the native
    /// branch, never to Accessibility — `resolvedSourceAppForCapture()`
    /// returns the last *non*-Tippi app by definition, so an AX write would
    /// land in the wrong process.
    func testSnapshotWithNativeTextViewResolvesToNative() {
        let textView = NSTextView()
        textView.string = "hello world"
        let snapshot = SelectionSnapshot(
            text: "hello",
            element: nil,
            range: nil,
            bounds: nil,
            sourceApp: nil,
            nativeTextView: textView,
            nativeRange: NSRange(location: 0, length: 5)
        )

        guard case .native(let resolved, let range) = ReplacementTarget(snapshot: snapshot) else {
            return XCTFail("expected .native for a snapshot carrying a native text view")
        }
        XCTAssertTrue(resolved === textView)
        XCTAssertEqual(range, NSRange(location: 0, length: 5))
    }

    /// Nothing captured at all — the bar still has to write somewhere.
    func testSnapshotWithoutAnyCaptureResolvesToBlind() {
        let snapshot = SelectionSnapshot(
            text: "hello",
            element: nil,
            range: nil,
            bounds: nil,
            sourceApp: nil,
            nativeTextView: nil,
            nativeRange: nil
        )

        guard case .blind = ReplacementTarget(snapshot: snapshot) else {
            return XCTFail("expected .blind when neither a native view nor an AX element was captured")
        }
    }

    // MARK: - Call site 2: hotkey flow (AppDelegate's `last*` state shape)

    /// `capturedReplacementTarget` feeds exactly these four values through.
    /// With the native pair populated the hotkey flow must not reach AX.
    func testHotkeyStateWithNativeTextViewResolvesToNative() {
        let textView = NSTextView()
        textView.string = "abc"

        let target = ReplacementTarget(
            nativeTextView: textView,
            nativeRange: NSRange(location: 0, length: 3),
            element: nil,
            range: nil,
            app: nil
        )

        guard case .native(let resolved, _) = target else {
            return XCTFail("expected .native for hotkey state captured inside Notes")
        }
        XCTAssertTrue(resolved === textView)
    }

    /// The ordinary cross-app case: an AX element was captured, no native view.
    func testHotkeyStateWithElementResolvesToAccessibility() {
        let target = ReplacementTarget(
            nativeTextView: nil,
            nativeRange: nil,
            element: AXUIElementCreateSystemWide(),
            range: CFRange(location: 0, length: 4),
            app: nil
        )

        guard case .accessibility(_, let range, _) = target else {
            return XCTFail("expected .accessibility when only an AX element was captured")
        }
        XCTAssertEqual(range.length, 4)
    }

    // MARK: - Call site 3: translate panel (all-parameters shape)

    /// The regression from 2026-09-19: translating a selection inside Notes
    /// resolved to the Accessibility ladder and wrote the translation into
    /// another app. With the native pair passed in, the target must be
    /// `.native` even though an AX element and a source app are *also*
    /// present — which is exactly what the translate capture hands over.
    func testTranslateParametersPreferNativeOverAccessibility() {
        let textView = NSTextView()
        textView.string = "guten tag"

        let target = ReplacementTarget(
            nativeTextView: textView,
            nativeRange: NSRange(location: 0, length: 5),
            element: AXUIElementCreateSystemWide(),
            range: CFRange(location: 0, length: 5),
            app: NSRunningApplication.current
        )

        guard case .native(let resolved, _) = target else {
            return XCTFail("a native capture must win over an AX element — this is the 2026-09-19 bug")
        }
        XCTAssertTrue(resolved === textView)
    }

    /// Translating in another app, where no AX element could be read: the
    /// panel still falls through to a blind replace rather than doing nothing.
    func testTranslateParametersWithoutElementResolveToBlind() {
        let target = ReplacementTarget(
            nativeTextView: nil,
            nativeRange: nil,
            element: nil,
            range: nil,
            app: NSRunningApplication.current
        )

        guard case .blind(let app) = target else {
            return XCTFail("expected .blind when nothing was captured")
        }
        XCTAssertEqual(app?.processIdentifier, NSRunningApplication.current.processIdentifier)
    }

    // MARK: - Partial captures

    /// A text view without a range (or a range without a view) is not a usable
    /// native target — half a capture must fall through, not crash or write to
    /// a guessed range.
    func testHalfNativeCaptureFallsThrough() {
        let textView = NSTextView()

        guard case .blind = ReplacementTarget(
            nativeTextView: textView, nativeRange: nil, element: nil, range: nil, app: nil
        ) else {
            return XCTFail("a native text view without a range must not resolve to .native")
        }

        guard case .blind = ReplacementTarget(
            nativeTextView: nil, nativeRange: NSRange(location: 0, length: 1), element: nil, range: nil, app: nil
        ) else {
            return XCTFail("a native range without a text view must not resolve to .native")
        }
    }

    /// Same rule on the AX side.
    func testHalfAccessibilityCaptureFallsThrough() {
        guard case .blind = ReplacementTarget(
            nativeTextView: nil, nativeRange: nil, element: AXUIElementCreateSystemWide(), range: nil, app: nil
        ) else {
            return XCTFail("an AX element without a range must not resolve to .accessibility")
        }
    }

    // MARK: - Writing

    /// The native write actually replaces the range (and only the range), via
    /// the `shouldChangeText`/`didChangeText` bracket that keeps undo working.
    @MainActor
    func testNativeWriteReplacesOnlyTheGivenRange() async {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.string = "hello world"

        await ReplacementWriter.write(
            "goodbye",
            to: .native(textView, NSRange(location: 0, length: 5))
        )

        XCTAssertEqual(textView.string, "goodbye world")
    }

    /// An identity write still goes through the same path — the caller
    /// (`performSelectionAction`) is what filters no-op transforms, and it
    /// must keep doing so: writing identical text is indistinguishable from
    /// "the app ignored the write" further down the ladder.
    @MainActor
    func testNativeWriteOfIdenticalTextLeavesTextUnchanged() async {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.string = "hello world"

        await ReplacementWriter.write(
            "hello",
            to: .native(textView, NSRange(location: 0, length: 5))
        )

        XCTAssertEqual(textView.string, "hello world")
    }

    /// A captured range that no longer fits the document must be dropped.
    ///
    /// This is not hypothetical: the range is captured when the trigger fires,
    /// the AI round-trip takes seconds, and the user can delete text in the
    /// note meanwhile. Without the bounds check in `writeNative`, this very
    /// call aborted the test host outright ("freed pointer was not the last
    /// allocation") — `NSTextView.shouldChangeText(in:)` does not refuse an
    /// out-of-bounds range, it corrupts the heap. Measured 2026-09-19.
    @MainActor
    func testNativeWriteWithStaleRangeIsDroppedInsteadOfCrashing() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.string = "short"

        ReplacementWriter.writeNative("x", in: textView, range: NSRange(location: 99, length: 5))
        XCTAssertEqual(textView.string, "short", "a range past the end must be dropped")

        // Partially stale: starts inside the document but runs past the end.
        ReplacementWriter.writeNative("x", in: textView, range: NSRange(location: 3, length: 40))
        XCTAssertEqual(textView.string, "short", "a range overrunning the end must be dropped")

        // `NSNotFound` is what a failed range lookup yields — never a location.
        ReplacementWriter.writeNative("x", in: textView, range: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(textView.string, "short", "NSNotFound must never be treated as a position")

        // Exactly at the end is legal — an insertion point after the last
        // character, not a stale range. It must still go through.
        ReplacementWriter.writeNative("!", in: textView, range: NSRange(location: 5, length: 0))
        XCTAssertEqual(textView.string, "short!", "an empty range at the very end is a valid insertion point")
    }
}
