import AppKit
import XCTest
@testable import Tippi

/// `firstDescendant(ofType:)` is what makes the Notes font-panel button find
/// the note's text view to focus before the panel opens (see
/// `NotesRootView`'s font button) — a plain view-tree search, testable
/// without any window/app/iCloud machinery.
final class NSViewFirstDescendantTests: XCTestCase {
    func testFindsDirectSubview() {
        let root = NSView()
        let target = NSTextField()
        root.addSubview(target)
        XCTAssertTrue(root.firstDescendant(ofType: NSTextField.self) === target)
    }

    func testFindsDeeplyNestedSubview() {
        let root = NSView()
        let middle = NSView()
        let target = NSTextView()
        root.addSubview(middle)
        middle.addSubview(target)
        XCTAssertTrue(root.firstDescendant(ofType: NSTextView.self) === target)
    }

    func testReturnsNilWhenNoMatch() {
        let root = NSView()
        root.addSubview(NSView())
        XCTAssertNil(root.firstDescendant(ofType: NSTextView.self))
    }

    /// A view matching a broader supertype (`NSTextView`) must not shadow a
    /// search for the more specific subclass actually used by the app —
    /// exercises the exact call site's real type, not just any `NSTextView`.
    func testMatchesSpecificSubclassNotJustSuperclass() {
        let root = NSView()
        let plainTextView = NSTextView()
        root.addSubview(plainTextView)
        XCTAssertNil(root.firstDescendant(ofType: PlainTextEditor.PasteAwareTextView.self))

        let target = PlainTextEditor.PasteAwareTextView()
        root.addSubview(target)
        XCTAssertTrue(root.firstDescendant(ofType: PlainTextEditor.PasteAwareTextView.self) === target)
    }
}
