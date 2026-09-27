import XCTest
@testable import Tippi

/// Pure decisions behind the audit fixes of 2026-09-27 that have no other test home.
final class BlockOneAuditFixTests: XCTestCase {

    // MARK: - Notes editor adopts the other Mac's version only when clean

    func testEditorAdoptsExternalVersionWhenNothingUnsaved() {
        XCTAssertEqual(NotesEditorView.adoptedText(external: "neu vom Mac mini", text: "alt", lastSaved: "alt"),
                       "neu vom Mac mini")
    }

    func testEditorKeepsUnsavedLocalEdits() {
        XCTAssertNil(NotesEditorView.adoptedText(external: "neu vom Mac mini", text: "alt + getippt", lastSaved: "alt"))
    }

    func testEditorIgnoresEchoOfItsOwnSave() {
        XCTAssertNil(NotesEditorView.adoptedText(external: "gleich", text: "gleich", lastSaved: "gleich"))
    }

    // MARK: - No write when the result equals the selection (doubling bug)

    @MainActor
    func testIdenticalResultIsUnchanged() {
        XCTAssertTrue(ReplacementWriter.isUnchanged("Hallo Welt.", original: "Hallo Welt.\n"))
    }

    @MainActor
    func testChangedResultIsWritten() {
        XCTAssertFalse(ReplacementWriter.isUnchanged("Hallo Welt.", original: "hallo welt"))
    }

    @MainActor
    func testUnknownOriginalIsWritten() {
        XCTAssertFalse(ReplacementWriter.isUnchanged("Hallo", original: nil))
    }

    // MARK: - Stream failures reported inside a 200 response

    func testStreamErrorObjectThrows() {
        XCTAssertThrowsError(try OpenAIStreamLine.parse(#"data: {"error":{"message":"upstream overloaded"}}"#))
    }

    func testStreamFinishReasonErrorThrows() {
        let line = #"data: {"choices":[{"delta":{"content":""},"finish_reason":"error"}]}"#
        XCTAssertThrowsError(try OpenAIStreamLine.parse(line))
    }

    func testStreamContentFilterThrows() {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#
        XCTAssertThrowsError(try OpenAIStreamLine.parse(line))
    }

    func testStreamDeltaAndLengthAndDone() throws {
        XCTAssertEqual(try OpenAIStreamLine.parse(#"data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}"#),
                       .delta("Hi", truncated: false))
        XCTAssertEqual(try OpenAIStreamLine.parse(#"data: {"choices":[{"delta":{"content":"x"},"finish_reason":"length"}]}"#),
                       .delta("x", truncated: true))
        XCTAssertEqual(try OpenAIStreamLine.parse("data: [DONE]"), .done)
        XCTAssertNil(try OpenAIStreamLine.parse(": keep-alive"))
    }

    func testEmptyResultThrows() {
        XCTAssertThrowsError(try LLMError.nonEmpty("  \n"))
        XCTAssertEqual(try? LLMError.nonEmpty(" Hallo "), "Hallo")
    }

    // MARK: - Notes reload keeps a save that happened during the reload

    func testReloadKeepsNewerInMemoryVersion() {
        let id = UUID()
        let disk = Note(id: id, content: "alt", modifiedAt: Date(timeIntervalSince1970: 100))
        let mine = Note(id: id, content: "neu", modifiedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(NotesStore.preferNewer(loaded: [disk], current: [mine]).first?.content, "neu")
    }

    func testReloadTakesNewerDiskVersion() {
        let id = UUID()
        let disk = Note(id: id, content: "vom Mac mini", modifiedAt: Date(timeIntervalSince1970: 300))
        let mine = Note(id: id, content: "alt", modifiedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(NotesStore.preferNewer(loaded: [disk], current: [mine]).first?.content, "vom Mac mini")
    }

    func testReloadDropsNotesDeletedOnDisk() {
        let gone = Note(content: "gelöscht", modifiedAt: Date(timeIntervalSince1970: 999))
        XCTAssertTrue(NotesStore.preferNewer(loaded: [], current: [gone]).isEmpty)
    }
}
