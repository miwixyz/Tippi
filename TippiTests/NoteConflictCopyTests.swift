import XCTest
@testable import Tippi

/// Audit 2026-11-17, Fund 1: Zwei Dateien derselben Notiz (gleiche UUID, verschiedene
/// Titel) entstehen, wenn zwei Macs die erste Zeile im selben Sync-Fenster ändern. Bis
/// dahin löschte Tippi eine davon endgültig. Nur ein exaktes Duplikat oder die eigene
/// Vorgängerfassung darf verschwinden, alles andere bleibt als Konfliktkopie.
final class NoteConflictCopyTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") }.sorted()
    }

    private func contents() throws -> [String] {
        try files().map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }.sorted()
    }

    private func writeRaw(_ name: String, _ content: String, modified: Date) throws {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    // MARK: Speichern

    func testRenameRemovesOnlyTheOwnPredecessor() throws {
        let id = UUID()
        let old = Note(id: id, content: "Alt\nText")
        try NotesStore.writeNoteFile(old, to: dir)
        try NotesStore.writeNoteFile(Note(id: id, content: "Neu\nText"), to: dir, previousContent: old.content)
        XCTAssertEqual(try files(), ["Neu — \(id.uuidString).txt"])
    }

    func testSaveKeepsAVersionFromTheOtherMac() throws {
        let id = UUID()
        // Mac B hat umbenannt; hier war die Notiz offen und kannte nur „Alt“.
        try NotesStore.writeNoteFile(Note(id: id, content: "Y\nvon B"), to: dir, pruneStale: false)
        try NotesStore.writeNoteFile(Note(id: id, content: "X\nvon A"), to: dir, previousContent: "Alt\nText")

        XCTAssertEqual(try contents(), ["X\nvon A", "Y\nvon B"], "keine Fassung darf verloren gehen")
        XCTAssertTrue(try files().contains("X — \(id.uuidString).txt"))
        let copyID = NotesStore.conflictCopyID(of: id, content: "Y\nvon B")
        XCTAssertTrue(try files().contains("Y — \(copyID.uuidString).txt"), "Kopie unter eigener Kennung")
    }

    @MainActor
    func testEditorSaveKeepsTheOtherMacsRename() async throws {
        let store = NotesStore(directory: dir, refreshOnInit: false)
        var note = store.create()
        note.content = "L\nmein"
        store.save(note)
        await store.waitForPendingOperations()
        // Mac B hat umbenannt; der Editor hier tippt weiter auf seiner Fassung „L“.
        try NotesStore.writeNoteFile(Note(id: note.id, content: "O\nvon B"), to: dir, pruneStale: false)
        note.content = "T\nmein, weiter"
        store.save(note, basedOn: "L\nmein")
        await store.waitForPendingOperations()
        XCTAssertEqual(try contents(), ["O\nvon B", "T\nmein, weiter"])
    }

    @MainActor
    func testQuitWriteRemovesItsOwnPredecessor() async throws {
        let store = NotesStore(directory: dir, refreshOnInit: false)
        var note = store.create()
        note.content = "Alt\nText"
        store.save(note)
        await store.waitForPendingOperations()
        await Task.yield()   // Zähler laufender Schreibvorgänge zurück auf null
        store.noteUnsavedEdit(id: note.id, content: "Neu\nText", basedOn: "Alt\nText")
        store.flushUnsavedEditSynchronously()
        XCTAssertEqual(try files(), ["Neu — \(note.id.uuidString).txt"], "⌘Q direkt nach Titeländerung: keine Konfliktkopie")
    }

    // MARK: Laden

    func testLoadKeepsADivergingDuplicateAsConflictCopy() throws {
        let id = UUID()
        try writeRaw("X — \(id.uuidString).txt", "X\nneuer", modified: Date(timeIntervalSince1970: 2_000))
        try writeRaw("Y — \(id.uuidString).txt", "Y\nälter", modified: Date(timeIntervalSince1970: 1_000))

        let first = NotesStore.loadAllNotes(from: dir)
        XCTAssertEqual(first.map(\.content).sorted(), ["X\nneuer", "Y\nälter"])
        XCTAssertEqual(first.first { $0.id == id }?.content, "X\nneuer", "die neuere behält die Kennung")
        XCTAssertEqual(try contents(), ["X\nneuer", "Y\nälter"])

        let second = NotesStore.loadAllNotes(from: dir)
        XCTAssertEqual(second.count, 2, "erneutes Laden erzeugt keine weitere Kopie")
        XCTAssertEqual(try files().count, 2)
    }

    func testLoadRemovesAnExactDuplicate() throws {
        let id = UUID()
        try writeRaw("Titel — \(id.uuidString).txt", "Titel\ngleich", modified: Date(timeIntervalSince1970: 2_000))
        try writeRaw("\(id.uuidString).txt", "Titel\ngleich", modified: Date(timeIntervalSince1970: 1_000))

        let notes = NotesStore.loadAllNotes(from: dir)
        XCTAssertEqual(notes.map(\.id), [id])
        XCTAssertEqual(try files(), ["Titel — \(id.uuidString).txt"])
    }

    func testAnExistingCopyIsNeverOverwritten() throws {
        let id = UUID()
        let copyID = NotesStore.conflictCopyID(of: id, content: "Y\nälter")
        // Der andere Mac hat die Kopie schon angelegt, der Nutzer hat sie danach bearbeitet.
        try writeRaw("Y — \(copyID.uuidString).txt", "Y\nälter, ergänzt", modified: Date(timeIntervalSince1970: 3_000))
        try writeRaw("X — \(id.uuidString).txt", "X\nneuer", modified: Date(timeIntervalSince1970: 2_000))
        try writeRaw("Y — \(id.uuidString).txt", "Y\nälter", modified: Date(timeIntervalSince1970: 1_000))

        _ = NotesStore.loadAllNotes(from: dir)
        XCTAssertEqual(try contents(), ["X\nneuer", "Y\nälter, ergänzt"])
    }

    // MARK: Kennung

    func testConflictCopyIDIsStablePerVersion() {
        let id = UUID()
        let a = NotesStore.conflictCopyID(of: id, content: "Text")
        XCTAssertEqual(a, NotesStore.conflictCopyID(of: id, content: "Text"), "beide Macs kommen auf dieselbe Kopie")
        XCTAssertNotEqual(a, NotesStore.conflictCopyID(of: id, content: "Text 2"))
        XCTAssertNotEqual(a, id)
        XCTAssertEqual(a.uuidString[a.uuidString.index(a.uuidString.startIndex, offsetBy: 14)], "5")
    }
}
