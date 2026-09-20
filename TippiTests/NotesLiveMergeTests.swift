import XCTest
@testable import Tippi

/// Covers `NotesStore.merge` — the decision the live sync makes when a note
/// file changes on the other Mac.
///
/// Every case here is a way this feature could destroy work. Notes are
/// hard-deleted without a trash (`NotesStore.delete`), and the editor keeps the
/// text in its own `@State` until a 600 ms autosave fires, so there are two
/// windows where the only copy of something lives somewhere the merge can
/// overwrite.
final class NotesLiveMergeTests: XCTestCase {

    /// Two helpers rather than one with a defaulted first parameter: Swift
    /// cannot skip a defaulted *positional* argument, so `note("x", date)`
    /// would not compile against `note(_ id: UUID = UUID(), ...)`.
    private func note(_ content: String, _ modified: Date) -> Note {
        Note(id: UUID(), content: content, createdAt: modified, modifiedAt: modified)
    }

    private func note(id: UUID, _ content: String, _ modified: Date) -> Note {
        Note(id: id, content: content, createdAt: modified, modifiedAt: modified)
    }

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    // MARK: - The ordinary case

    func testNewNoteFromTheOtherMacIsAdded() {
        let incoming = note("written over there", newer)
        let (result, heldBack) = NotesStore.merge([incoming], into: [], skipping: nil)

        XCTAssertEqual(result.map(\.content), ["written over there"])
        XCTAssertFalse(heldBack)
    }

    func testNewerVersionReplacesOlderOne() {
        let id = UUID()
        let mine = note(id: id, "old text", older)
        let theirs = note(id: id, "new text", newer)

        let (result, _) = NotesStore.merge([theirs], into: [mine], skipping: nil)

        XCTAssertEqual(result.count, 1, "Same id must update in place, not duplicate.")
        XCTAssertEqual(result.first?.content, "new text")
    }

    // MARK: - The ways this could lose work

    func testOlderVersionCannotUndoANewerLocalEdit() {
        // A file that finishes downloading late carries an older timestamp.
        // Writing it in would silently revert an edit made here since.
        let id = UUID()
        let mine = note(id: id, "what I just typed", newer)
        let theirs = note(id: id, "stale version from the container", older)

        let (result, _) = NotesStore.merge([theirs], into: [mine], skipping: nil)

        XCTAssertEqual(result.first?.content, "what I just typed")
    }

    func testTheNoteOpenInTheEditorIsNeverTouched() {
        // The editor holds the text in @State and autosaves 600 ms after the
        // last keystroke. Replacing the model mid-sentence discards characters
        // that exist nowhere else.
        let id = UUID()
        let beingEdited = note(id: id, "half a sen", older)
        let theirs = note(id: id, "whatever the other Mac has", newer)

        let (result, heldBack) = NotesStore.merge([theirs], into: [beingEdited], skipping: id)

        XCTAssertEqual(result.first?.content, "half a sen", "The open note must survive untouched.")
        XCTAssertTrue(heldBack, "The UI has to be able to say a change was withheld.")
    }

    func testHoldingBackOneNoteDoesNotBlockTheOthers() {
        let editedID = UUID()
        let otherID = UUID()
        let existing = [note(id: editedID, "being typed", older), note(id: otherID, "old", older)]
        let incoming = [note(id: editedID, "ignored", newer), note(id: otherID, "updated", newer)]

        let (result, heldBack) = NotesStore.merge(incoming, into: existing, skipping: editedID)

        XCTAssertEqual(result.first(where: { $0.id == editedID })?.content, "being typed")
        XCTAssertEqual(result.first(where: { $0.id == otherID })?.content, "updated")
        XCTAssertTrue(heldBack)
    }

    func testMergeNeverRemovesANote() {
        // The contract that keeps absence from becoming deletion. In a ubiquity
        // container a missing file can mean evicted, not-yet-downloaded or
        // mid-rename — and a deleted note has no trash to come back from.
        let keep = note("nothing in the incoming set mentions me", older)
        let incoming = [note("a different note", newer)]

        let (result, _) = NotesStore.merge(incoming, into: [keep], skipping: nil)

        XCTAssertTrue(
            result.contains(where: { $0.id == keep.id }),
            "merge() dropped an existing note — absence must never be read as deletion."
        )
        XCTAssertEqual(result.count, 2)
    }

    func testEmptyIncomingSetChangesNothing() {
        let existing = [note("a", older), note("b", newer)]
        let (result, heldBack) = NotesStore.merge([], into: existing, skipping: nil)

        XCTAssertEqual(Set(result.map(\.id)), Set(existing.map(\.id)))
        XCTAssertFalse(heldBack)
    }

    // MARK: - Ordering

    func testResultIsSortedNewestFirst() {
        let old = note("older", older)
        let new = note("newer", newer)
        let (result, _) = NotesStore.merge([old], into: [new], skipping: nil)

        XCTAssertEqual(result.map(\.content), ["newer", "older"],
                       "The list is presented newest-first; the merge must not disturb that.")
    }
}
