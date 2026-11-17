import CryptoKit
import Foundation
import os

private let duplicatesLog = Logger(subsystem: "com.tippi.app", category: "notes-store")

// MARK: - Loading and duplicate files (audit 2026-11-17, finding 1)

extension NotesStore {
    /// Lists every note file in `directory`. Any ubiquitous item not yet
    /// downloaded locally is skipped this pass (download is kicked off, it
    /// will appear on the next `refresh()`) rather than blocking here.
    ///
    /// Also self-heals duplicate-UUID files — a real bug (fixed 2026-09-13
    /// in `writeNoteFile`) could leave a note's previous filename behind
    /// after a title-triggered rename, rendering as a ghost duplicate.
    ///
    /// Only an exact duplicate is deleted. Two files with the same UUID and
    /// different text are two versions — the first line changed on two Macs
    /// within one sync window gives each its own filename. Until 2026-11-17
    /// the older one was removed for good; now it stays as a conflict copy.
    nonisolated static func loadAllNotes(from directory: URL) -> [Note] {
        loadAllNotesAndPending(from: directory).notes
    }

    /// `pending`: notes whose file exists but is still downloading (an older
    /// local copy, a dataless file or a `.icloud` placeholder). They are not
    /// deleted, only not readable yet, so `refresh` keeps the in-memory
    /// version instead of dropping the note — the open note used to vanish
    /// from the editor for seconds (audit 2026-11-17, finding 6).
    nonisolated static func loadAllNotesAndPending(from directory: URL) -> (notes: [Note], pending: Set<UUID>) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]
        ) else {
            return ([], [])
        }

        var bestByID: [UUID: (note: Note, url: URL)] = [:]
        var older: [(note: Note, url: URL)] = []
        var pending: Set<UUID> = []

        for url in entries {
            guard url.pathExtension == fileExtension else {
                if url.pathExtension == "icloud", let id = cloudNoteID(in: url) { pending.insert(id) }
                continue
            }
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               status != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                if let id = cloudNoteID(in: url) { pending.insert(id) }
                continue
            }
            guard let note = readNoteFile(at: url) else { continue }
            if let existing = bestByID[note.id] {
                if note.modifiedAt > existing.note.modifiedAt {
                    older.append(existing)
                    bestByID[note.id] = (note, url)
                } else {
                    older.append((note, url))
                }
            } else {
                bestByID[note.id] = (note, url)
            }
        }

        var copies: [Note] = []
        for duplicate in older {
            if duplicate.note.content == bestByID[duplicate.note.id]?.note.content {
                duplicatesLog.notice("removing an exact duplicate note file")
                try? deleteFile(at: duplicate.url)
            } else if let copy = keepAsConflictCopy(duplicate.note, at: duplicate.url, in: directory, entries: entries) {
                copies.append(copy)
            }
        }

        return (bestByID.values.map(\.note) + copies, pending)
    }

    /// Moves a diverging version of a note to its own note instead of deleting
    /// it: write the copy first, remove the original only once that succeeded,
    /// so a failure never leaves zero copies. Returns the copy — or `nil` when
    /// it already existed (then only the original is removed) or the write failed
    /// (then the original stays and the next load tries again).
    ///
    /// The copy's UUID is derived from the original UUID and the text, so two
    /// Macs that resolve the same duplicate independently write the *same* file
    /// instead of two copies. If that file is already there (possibly still a
    /// `.icloud` placeholder), it is never overwritten: the user may have
    /// edited the copy since.
    @discardableResult
    nonisolated static func keepAsConflictCopy(
        _ version: Note, at url: URL, in directory: URL, entries: [URL]? = nil
    ) -> Note? {
        let copy = Note(id: conflictCopyID(of: version.id, content: version.content), content: version.content)
        let listing = entries ?? (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let exists = listing.contains { cloudNoteID(in: $0) == copy.id }
        if !exists {
            do {
                try writeNoteFile(copy, to: directory, pruneStale: false)
            } catch {
                duplicatesLog.error("conflict copy failed — diverging version kept in place: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        try? deleteFile(at: url)
        duplicatesLog.notice("kept a diverging note version as a conflict copy")
        return exists ? nil : copy
    }

    /// Name-based UUID (version-5 layout) from note id + text.
    nonisolated static func conflictCopyID(of id: UUID, content: String) -> UUID {
        let b = Array(SHA256.hash(data: Data((id.uuidString + "\n" + content).utf8)))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], (b[6] & 0x0F) | 0x50, b[7],
                           (b[8] & 0x3F) | 0x80, b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
