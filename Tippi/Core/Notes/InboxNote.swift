import Foundation

/// Sprachnotiz (Michael 2026-11-14): Diktate über ⌃⌥⌘N landen mit Zeitstempel unten in einer festen Notiz
/// „Eingang“ statt am Cursor. Design: `docs/SECURE-DESIGN-sprachnotiz.md`.
///
/// Die Notiz wird über ihren Titel gefunden, nicht über eine gespeicherte ID: Mac mini und MacBook teilen die
/// Notizen über iCloud, eine nur lokal gemerkte ID ergäbe auf dem zweiten Mac eine zweite „Eingang“.
@MainActor
enum InboxNote {
    enum Outcome: Equatable {
        /// Angehängt; `created` = die Notiz gab es noch nicht.
        case appended(created: Bool)
        /// Notizen nach `loadTimeout` noch nicht geladen – lieber nichts anlegen als eine zweite „Eingang“.
        case notLoaded
        /// „Eingang“ ist gerade in einem Editor offen. Dessen `@State` würde das Angehängte beim nächsten
        /// Autosave überschreiben (`NotesStore.noteBeingEdited`).
        case openInEditor
        /// Nur Leerraum erkannt (Whisper wirft bei Stille nicht wie Parakeet) – kein leerer Eintrag.
        case nothingToAdd
    }

    static var title: String { String(localized: "inbox.note.title") }
    nonisolated static let loadTimeout: Duration = .seconds(5)

    /// Ältester Treffer mit genau diesem Titel – fest, damit zwei Macs dieselbe Notiz wählen.
    nonisolated static func find(in notes: [Note], title: String) -> Note? {
        notes.filter { $0.title == title }.min { $0.createdAt < $1.createdAt }
    }

    /// Neuer Inhalt: Titelzeile (falls die Notiz neu ist), Leerzeile, „Zeitstempel – Text“ unten angehängt.
    nonisolated static func appending(_ text: String, to content: String?, title: String, stamp: String) -> String {
        let entry = stamp + " – " + text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content else { return title + "\n\n" + entry + "\n" }
        let body = content.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return body + "\n\n" + entry + "\n"
    }

    nonisolated static func stamp(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.locale(locale).day().month(.twoDigits).hour().minute())
    }

    /// „Eingang“ finden oder (nur mit Titelzeile) anlegen – fürs Panel beim Diktatbeginn. Nur nach `hasLoaded`
    /// aufrufen, sonst entstünde eine zweite.
    static func ensure(in store: NotesStore) -> Note {
        if let note = find(in: store.notes, title: title) { return note }
        var note = store.create()
        note.content = title + "\n"
        store.save(note)
        return note
    }

    /// Hängt `text` an „Eingang“ an (legt sie bei Bedarf an). Liest den Inhalt erst jetzt frisch aus dem
    /// Speicher – nie einen Stand vom Aufnahmebeginn.
    static func append(_ text: String, store: NotesStore, now: Date = Date(),
                       loadTimeout: Duration = InboxNote.loadTimeout) async -> Outcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .nothingToAdd }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: loadTimeout)
        while !store.hasLoaded, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard store.hasLoaded else { return .notLoaded }
        let title = Self.title
        let stamp = Self.stamp(now)
        if var note = find(in: store.notes, title: title) {
            if store.noteBeingEdited == note.id { return .openInEditor }
            note.content = appending(text, to: note.content, title: title, stamp: stamp)
            store.save(note)
            return .appended(created: false)
        }
        var note = store.create()
        note.content = appending(text, to: nil, title: title, stamp: stamp)
        store.save(note)
        return .appended(created: true)
    }
}
