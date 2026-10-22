import Foundation
import os

private let creationIndexLog = Logger(subsystem: "com.tippi.app", category: "notes-store")

/// Erstellungsdatum je Notiz, geteilt mit TippAI (`.notes-created.json` im Notizordner).
/// Gleiche Datei, gleiches Format, gleiche Regeln wie `TippAI/Storage/NoteCreationIndex.swift`
/// — Änderungen immer in beiden Repos.
///
/// Warum eine eigene Datei: Beide Apps speichern Notizen atomar (neue Datei ersetzt die alte),
/// dabei setzt macOS das Erstellungsdatum der Datei jedes Mal neu. Gemessen am 22.10.2026 an
/// 29 echten Notizen: Erstellt = Geändert bei allen 29. Sortieren nach „Erstellt“ braucht
/// deshalb einen eigenen, dauerhaften Wert.
///
/// Zusammenführen: Je UUID gewinnt das **früheste** Datum. Das ist ohne Abstimmung zwischen
/// Geräten und Apps konfliktfrei — wer zuletzt schreibt, kann nichts Älteres verlieren.
/// Die Datei enthält nur UUIDs und Zeitpunkte, keinen Notiztext.
enum NoteCreationIndex {
    static let filename = ".notes-created.json"
    static let currentVersion = 1
    static let maximumSize = 1_048_576
    static let maximumEntries = 20_000
    /// Frühestes plausibles Datum (01.01.2000). Älteres oder Zukünftiges wird verworfen.
    static let earliestDate = Date(timeIntervalSince1970: 946_684_800)

    enum Contents: Equatable {
        /// Gelesene, geprüfte Einträge (fehlende oder kaputte Datei: leer).
        case entries([UUID: Date])
        /// Datei aus einer neueren Version: nur lesen, nie überschreiben.
        case newerVersion([UUID: Date])

        var entries: [UUID: Date] {
            switch self {
            case .entries(let value), .newerVersion(let value): value
            }
        }
    }

    private struct Document: Codable {
        var version: Int
        var created: [String: Double]
    }

    // MARK: - Reine Logik (getestet)

    static func decode(_ data: Data, now: Date = Date()) -> Contents {
        guard data.count <= maximumSize,
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.created.count <= maximumEntries else { return .entries([:]) }
        let latest = now.addingTimeInterval(24 * 60 * 60)
        var result: [UUID: Date] = [:]
        for (raw, seconds) in document.created {
            guard let id = UUID(uuidString: raw), seconds.isFinite else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            guard date >= earliestDate, date <= latest else { continue }
            result[id] = date
        }
        return document.version > currentVersion ? .newerVersion(result) : .entries(result)
    }

    static func encode(_ entries: [UUID: Date]) throws -> Data {
        let kept = entries.count <= maximumEntries ? entries
            : Dictionary(uniqueKeysWithValues: entries.sorted { $0.value > $1.value }.prefix(maximumEntries)
                .map { ($0.key, $0.value) })
        let document = Document(
            version: currentVersion,
            created: Dictionary(uniqueKeysWithValues: kept.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumSize else { throw CocoaError(.fileWriteOutOfSpace) }
        return data
    }

    /// Je UUID das früheste Datum.
    static func merged(_ lhs: [UUID: Date], _ rhs: [UUID: Date]) -> [UUID: Date] {
        lhs.merging(rhs) { min($0, $1) }
    }

    /// Setzt `createdAt` aus dem Index. Notizen ohne Eintrag bekommen das frühere ihrer beiden
    /// Datei-Daten und landen in `missing`, damit sie einmalig nachgetragen werden.
    static func apply(_ index: [UUID: Date], to notes: [Note]) -> (notes: [Note], missing: [UUID: Date]) {
        var missing: [UUID: Date] = [:]
        let updated = notes.map { note -> Note in
            var note = note
            if let created = index[note.id] {
                note.createdAt = created
            } else {
                note.createdAt = min(note.createdAt, note.modifiedAt)
                missing[note.id] = note.createdAt
            }
            return note
        }
        return (updated, missing)
    }

    /// Externe Änderung: Die Datei kennt das Erstellungsdatum nicht — bekanntes behalten.
    static func keepingCreation(of known: [Note], for incoming: [Note]) -> [Note] {
        let createdByID = Dictionary(known.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { first, _ in first })
        return incoming.map { note in
            var note = note
            note.createdAt = createdByID[note.id] ?? min(note.createdAt, note.modifiedAt)
            return note
        }
    }

    // MARK: - Datei (koordiniert)

    /// Setzt `createdAt` aus dem Index und trägt fehlende Einträge einmalig nach (beim Laden).
    static func applyingIndex(to notes: [Note], in directory: URL) -> [Note] {
        let creation = read(in: directory)
        let applied = apply(creation.entries, to: notes)
        if case .entries = creation, !applied.missing.isEmpty {
            do {
                try update(in: directory, adding: applied.missing)
            } catch {
                creationIndexLog.error("creation index update failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return applied.notes
    }

    static func read(in directory: URL, now: Date = Date()) -> Contents {
        let url = directory.appendingPathComponent(filename)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumSize else { return .entries([:]) }
        var coordinatorError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            // Abgebildet statt geladen: Wächst die Datei nach der Größenprüfung, landet sie
            // nicht im Speicher — `decode` prüft die Größe vor dem Dekodieren.
            data = try? Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
        }
        guard coordinatorError == nil, let data else { return .entries([:]) }
        return decode(data, now: now)
    }

    /// Liest, führt zusammen und schreibt in **einem** koordinierten Schreibvorgang — so kann
    /// Tippi oder ein anderes Gerät nicht dazwischen schreiben. Eine Datei aus einer neueren
    /// Version bleibt unangetastet.
    static func update(in directory: URL, adding: [UUID: Date] = [:], removing: Set<UUID> = [],
                       now: Date = Date()) throws {
        guard !adding.isEmpty || !removing.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { coordinatedURL in
            do {
                var current: Contents = .entries([:])
                if let size = try? coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size <= maximumSize, let data = try? Data(contentsOf: coordinatedURL, options: .mappedIfSafe) {
                    current = decode(data, now: now)
                }
                guard case .entries(let existing) = current else { return }
                var next = merged(existing, adding)
                removing.forEach { next.removeValue(forKey: $0) }
                guard next != existing else { return }
                try encode(next).write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }
}

/// Sortierung der Notizliste (wie in TippAI): Geändert / Erstellt / Name.
enum NoteSortOrder: String, CaseIterable, Identifiable {
    case modified, created, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .modified: String(localized: "notes.sort.modified")
        case .created: String(localized: "notes.sort.created")
        case .title: String(localized: "notes.sort.title")
        }
    }

    /// Natürliche Richtung: Daten neueste zuerst, Namen A–Z. `reversed` dreht um.
    /// Gleichstand: zuletzt geändert zuerst, dann UUID — die Liste springt nie.
    static func sorted(_ notes: [Note], by order: NoteSortOrder, reversed: Bool = false) -> [Note] {
        notes.sorted { lhs, rhs in
            let primary: ComparisonResult
            switch order {
            case .modified: primary = compare(rhs.modifiedAt, lhs.modifiedAt)
            case .created: primary = compare(rhs.createdAt, lhs.createdAt)
            case .title: primary = sortTitle(lhs).localizedStandardCompare(sortTitle(rhs))
            }
            if primary != .orderedSame { return reversed ? primary == .orderedDescending : primary == .orderedAscending }
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Titel ohne führende Markdown-Zeichen (`# `, `> `, `- `), damit „# Einkauf“ unter E steht
    /// wie in TippAI, das Markdown im Titel ausblendet.
    static func sortTitle(_ note: Note) -> String {
        String(note.title.drop { "#>*-+ \t".contains($0) })
    }

    private static func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
}
