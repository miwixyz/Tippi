import XCTest
@testable import Tippi

/// Erstellungsdatum-Index (geteilt mit TippAI) und Sortierung der Notizliste.
/// Gleiche Fälle wie `TippAITests/NoteCreationIndexTests.swift` — beide Apps teilen die Datei.
final class NoteCreationIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    // MARK: - Lesen

    func testDecodeKeepsValidEntriesAndDropsInvalidOnes() {
        let data = json(["version": 1, "created": [
            idA.uuidString: 1_700_000_000.0,
            idB.uuidString: 100.0,                       // vor 2000
            "kein-uuid": 1_700_000_000.0,
            UUID().uuidString: now.timeIntervalSince1970 + 3 * 86_400, // Zukunft
        ]])
        XCTAssertEqual(NoteCreationIndex.decode(data, now: now),
                       .entries([idA: Date(timeIntervalSince1970: 1_700_000_000)]))
    }

    func testCorruptOrOversizedDataIsEmpty() {
        XCTAssertEqual(NoteCreationIndex.decode(Data("{kaputt".utf8), now: now), .entries([:]))
        XCTAssertEqual(NoteCreationIndex.decode(json(["version": 1, "created": ["x": "y"]]), now: now), .entries([:]))
        let big = Data(repeating: 0x20, count: NoteCreationIndex.maximumSize + 1)
        XCTAssertEqual(NoteCreationIndex.decode(big, now: now), .entries([:]))
    }

    func testTooManyEntriesIsIgnored() {
        var created: [String: Double] = [:]
        for _ in 0...NoteCreationIndex.maximumEntries { created[UUID().uuidString] = 1_700_000_000 }
        XCTAssertEqual(NoteCreationIndex.decode(json(["version": 1, "created": created]), now: now), .entries([:]))
    }

    func testNewerVersionIsReadOnly() {
        let data = json(["version": 2, "created": [idA.uuidString: 1_700_000_000.0]])
        guard case .newerVersion(let entries) = NoteCreationIndex.decode(data, now: now) else {
            return XCTFail("neuere Version muss als nur-lesen erkannt werden")
        }
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - Zusammenführen und Anwenden

    func testMergeKeepsEarliestDate() {
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late = Date(timeIntervalSince1970: 1_750_000_000)
        let merged = NoteCreationIndex.merged([idA: late, idB: early], [idA: early])
        XCTAssertEqual(merged, [idA: early, idB: early])
    }

    func testApplyUsesIndexAndReportsMissing() {
        let indexed = Date(timeIntervalSince1970: 1_600_000_000)
        let fileCreated = Date(timeIntervalSince1970: 1_780_000_000)
        let fileModified = Date(timeIntervalSince1970: 1_770_000_000)
        let notes = [
            Note(id: idA, content: "A", createdAt: fileCreated, modifiedAt: fileModified),
            Note(id: idB, content: "B", createdAt: fileCreated, modifiedAt: fileModified),
        ]
        let result = NoteCreationIndex.apply([idA: indexed], to: notes)
        XCTAssertEqual(result.notes[0].createdAt, indexed)
        // Ohne Eintrag: das frühere der beiden Datei-Daten, einmalig nachtragen.
        XCTAssertEqual(result.notes[1].createdAt, fileModified)
        XCTAssertEqual(result.missing, [idB: fileModified])
    }

    // MARK: - Datei

    func testUpdateRoundTripMergesAndRemoves() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tippi-created-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late = Date(timeIntervalSince1970: 1_750_000_000)

        try NoteCreationIndex.update(in: directory, adding: [idA: late, idB: late], now: now)
        try NoteCreationIndex.update(in: directory, adding: [idA: early], now: now)
        XCTAssertEqual(NoteCreationIndex.read(in: directory, now: now), .entries([idA: early, idB: late]))

        try NoteCreationIndex.update(in: directory, removing: [idB], now: now)
        XCTAssertEqual(NoteCreationIndex.read(in: directory, now: now), .entries([idA: early]))
    }

    func testUpdateNeverOverwritesNewerVersion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tippi-created-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(NoteCreationIndex.filename)
        let original = json(["version": 2, "created": [idA.uuidString: 1_700_000_000.0], "neu": true])
        try original.write(to: url)

        try NoteCreationIndex.update(in: directory, adding: [idB: now], now: now)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    // MARK: - Sortierung

    func testSortOrders() {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let apfel = Note(content: "Äpfel kaufen", createdAt: base, modifiedAt: base + 3 * day)
        let banane = Note(content: "# banane", createdAt: base + 2 * day, modifiedAt: base + day)
        let zebra = Note(content: "Zebra", createdAt: base + day, modifiedAt: base + 2 * day)
        let notes = [banane, zebra, apfel]

        XCTAssertEqual(NoteSortOrder.sorted(notes, by: .modified).map(\.id), [apfel.id, zebra.id, banane.id])
        XCTAssertEqual(NoteSortOrder.sorted(notes, by: .created).map(\.id), [banane.id, zebra.id, apfel.id])
        // A–Z: Ä wie A, Groß/klein egal, führende Markdown-Zeichen („# “) zählen nicht.
        XCTAssertEqual(NoteSortOrder.sorted(notes, by: .title).map(\.id), [apfel.id, banane.id, zebra.id])
        XCTAssertEqual(NoteSortOrder.sorted(notes, by: .title, reversed: true).map(\.id), [zebra.id, banane.id, apfel.id])
        XCTAssertEqual(NoteSortOrder.sorted(notes, by: .created, reversed: true).map(\.id), [apfel.id, zebra.id, banane.id])
    }

    func testTitleTieBreaksByModifiedDate() {
        let older = Note(content: "Gleich", modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = Note(content: "Gleich", modifiedAt: Date(timeIntervalSince1970: 1_700_100_000))
        XCTAssertEqual(NoteSortOrder.sorted([older, newer], by: .title).map(\.id), [newer.id, older.id])
    }
}
