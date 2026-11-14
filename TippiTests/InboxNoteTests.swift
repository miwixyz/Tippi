import XCTest
@testable import Tippi

/// Sprachnotiz (2026-11-14, docs/SECURE-DESIGN-sprachnotiz.md): Anhängen an „Eingang“, nie eine zweite
/// Notiz, nie still verloren, Deckkraft begrenzt, Kürzel frei.
@MainActor
final class InboxNoteTests: XCTestCase {

    private func makeStore() throws -> (NotesStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (NotesStore(directory: dir, refreshOnInit: false), dir)
    }

    // MARK: Format

    func testAppendingToNewAndExistingNote() {
        let fresh = InboxNote.appending("  Milch kaufen ", to: nil, title: "Eingang", stamp: "14.11., 14:52")
        XCTAssertEqual(fresh, "Eingang\n\n14.11., 14:52 – Milch kaufen\n")
        let more = InboxNote.appending("Kino anrufen", to: fresh + "\n\n  ", title: "Eingang", stamp: "14.11., 15:00")
        XCTAssertEqual(more, "Eingang\n\n14.11., 14:52 – Milch kaufen\n\n14.11., 15:00 – Kino anrufen\n",
                       "Leerraum am Ende wird nicht vervielfacht")
    }

    func testFindTakesOldestWithExactTitle() {
        let old = Note(content: "Eingang\n\nalt", createdAt: Date(timeIntervalSince1970: 100))
        let new = Note(content: "Eingang\n\nneu", createdAt: Date(timeIntervalSince1970: 200))
        let other = Note(content: "Eingangskorb", createdAt: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(InboxNote.find(in: [new, other, old], title: "Eingang")?.id, old.id)
        XCTAssertNil(InboxNote.find(in: [other], title: "Eingang"))
    }

    // MARK: Speicher

    func testAppendCreatesOnceThenAppends() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = await InboxNote.append("eins", store: store)
        XCTAssertEqual(first, .appended(created: true))
        let second = await InboxNote.append("zwei", store: store)
        XCTAssertEqual(second, .appended(created: false))
        let inboxes = store.notes.filter { $0.title == InboxNote.title }
        XCTAssertEqual(inboxes.count, 1, "nie eine zweite „Eingang“")
        let content = try XCTUnwrap(inboxes.first?.content)
        XCTAssertTrue(content.contains(" – eins\n\n"))
        XCTAssertTrue(content.hasSuffix(" – zwei\n"))
        await store.waitForPendingOperations()
    }

    /// Fix 14.11. (kein Fenster beim ersten Druck): Panel braucht „Eingang“ schon beim Diktatbeginn.
    func testEnsureCreatesOnceAndAppendKeepsTitle() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = InboxNote.ensure(in: store)
        XCTAssertEqual(InboxNote.ensure(in: store).id, first.id, "kein zweites Anlegen")
        _ = await InboxNote.append("hallo", store: store)
        let notes = store.notes.filter { $0.title == InboxNote.title }
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].content.hasPrefix(InboxNote.title + "\n\n"))
        XCTAssertTrue(notes[0].content.hasSuffix(" – hallo\n"))
        await store.waitForPendingOperations()
    }

    /// Code-Audit 14.11.: Stille über Whisper ergibt Leerraum – kein leerer Eintrag, keine neue Notiz.
    func testBlankTextAddsNothing() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await InboxNote.append(" \n ", store: store)
        XCTAssertEqual(outcome, .nothingToAdd)
        XCTAssertTrue(store.notes.isEmpty)
    }

    /// Reihenfolge Editor-Speichern → Anhängen (Gegenprüfung 14.11.): beides bleibt erhalten.
    func testEditorSaveBeforeAppendKeepsBoth() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await InboxNote.append("diktiert", store: store)
        var note = try XCTUnwrap(InboxNote.find(in: store.notes, title: InboxNote.title))
        note.content += "getippt im Editor\n"
        store.save(note)                     // so speichert `onDisappear` beim Schließen des Panels
        _ = await InboxNote.append("danach", store: store)
        let content = try XCTUnwrap(InboxNote.find(in: store.notes, title: InboxNote.title)?.content)
        XCTAssertTrue(content.contains("diktiert"))
        XCTAssertTrue(content.contains("getippt im Editor"))
        XCTAssertTrue(content.hasSuffix(" – danach\n"))
        await store.waitForPendingOperations()
    }

    func testOpenInEditorIsNotOverwritten() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await InboxNote.append("vorher", store: store)
        let note = try XCTUnwrap(InboxNote.find(in: store.notes, title: InboxNote.title))
        store.noteBeingEdited = note.id
        let outcome = await InboxNote.append("nachher", store: store)
        XCTAssertEqual(outcome, .openInEditor)
        XCTAssertEqual(InboxNote.find(in: store.notes, title: InboxNote.title)?.content, note.content,
                       "nicht angefasst – der Text geht stattdessen in die Zwischenablage")
        await store.waitForPendingOperations()
    }

    // MARK: Einstellungen

    func testOpacityIsClamped() {
        XCTAssertEqual(NotesSettings.clampedOpacity(nil), 1.0)
        XCTAssertEqual(NotesSettings.clampedOpacity(0.0), 0.35)
        XCTAssertEqual(NotesSettings.clampedOpacity(7), 1.0)
        XCTAssertEqual(NotesSettings.clampedOpacity(Double.nan), 1.0)
        XCTAssertEqual(NotesSettings.clampedOpacity("0.5"), 1.0, "nur Zahlen")
        XCTAssertEqual(NotesSettings.clampedOpacity(0.6), 0.6)
    }

    func testInboxNeverGetsLetterLayout() {
        XCTAssertFalse(DictationLayout.layoutWanted(source: .inbox, toggle: true, targetIsTerminal: false))
        XCTAssertTrue(DictationLayout.layoutWanted(source: .standard, toggle: true, targetIsTerminal: false))
    }

    func testVoiceNoteDefaultIsFree() {
        let others: [KeyCombo] = [.default, .dictationDefault, .translateDefault, .emojiDefault, .notesDefault,
                                  MailDictationSettings.safetyCombo]
        XCTAssertFalse(others.contains(.voiceNoteDefault))
        XCTAssertNotEqual(KeyCombo.voiceNoteDefault,
                          KeyCombo(keyCode: 35, modifiers: [.control, .option, .command]), "nicht die Pause ⌃⌥⌘P")
    }
}
