import Foundation
import os

private let notesLog = Logger(subsystem: "com.tippi.app", category: "notes-store")

/// Owns the notes list and its persistence.
///
/// Storage: one plain `.txt` file per note — no wrapper format, no lock-in,
/// readable/greppable/Spotlight-searchable directly in Finder. `createdAt`/
/// `modifiedAt` come from the file's own filesystem attributes rather than
/// being embedded, which is also what keeps a note file exactly its own
/// content and nothing else. Written into the app's iCloud Ubiquity
/// container (`iCloud.dev.mwlr.Tippi`, see `Tippi.entitlements`) so notes
/// appear on every Mac signed into the same iCloud account. Falls back to a
/// local directory when iCloud is unavailable (signed out, Documents & Data
/// off) — the feature always works, sync is a bonus, never a blocker.
///
/// Deliberately simple sync model for v1 (matches the agreed minimal scope):
/// - Refresh happens when the Notes window opens, not continuously — no
///   long-lived `NSMetadataQuery`.
/// - Conflict handling is last-write-wins by `modifiedAt`. Two Macs editing
///   the exact same note in the same few seconds is not a realistic scenario
///   for a single user's quick-notes list.
/// - A note just created on another Mac may not have finished downloading
///   from iCloud yet when this Mac refreshes; `startDownloadingUbiquitousItem`
///   is kicked off for any not-yet-local file, and it simply shows up on the
///   *next* refresh. No spinner/blocking wait — acceptable for how small
///   these files are and how infrequently this actually happens in practice.
///
/// Nothing here ever touches `NSUbiquitousKeyValueStore` (that's reserved for
/// window prefs in `NotesPreferences`) and nothing here ever handles API
/// keys/credentials — those stay local/Keychain, unrelated to this store.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [Note] = []
    @Published private(set) var isUsingiCloud: Bool = false
    @Published var loadError: String?

    /// Resolved during `refresh()` and reused by `save`/`delete` for the rest
    /// of the session, so every mutation doesn't re-resolve the ubiquity
    /// container. A change in iCloud availability is picked up on the next
    /// `refresh()` (i.e. next time the Notes window opens) — consistent with
    /// the "refresh on open, not live" model above.
    private var currentDirectory: URL = NotesStore.localFallbackDirectory

    private nonisolated static let migratedDefaultsKey = "tippi.notes.migratedToiCloud.v1"
    private nonisolated static let fileExtension = "txt"

    private init() {
        refresh()
    }

    // MARK: - Public API

    /// Re-resolves storage location (iCloud vs. local fallback), migrates
    /// local notes into iCloud the first time it becomes available, and
    /// reloads the list from disk. Call when the Notes window opens.
    func refresh() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let (directory, usingiCloud) = Self.resolveStorageDirectory()
            if usingiCloud {
                Self.migrateLocalNotesIfNeeded(into: directory)
            }
            let loaded = Self.loadAllNotes(from: directory)
            await MainActor.run {
                self.currentDirectory = directory
                self.isUsingiCloud = usingiCloud
                self.notes = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
                self.loadError = nil
            }
        }
    }

    /// Creates a blank note, inserts it at the top of the list, and persists
    /// it immediately so it exists on disk even if the user never types
    /// anything before switching away.
    @discardableResult
    func create() -> Note {
        let note = Note()
        notes.insert(note, at: 0)
        persist(note)
        return note
    }

    /// Saves (creates or updates) a note. Bumps `modifiedAt` to now for
    /// immediate, optimistic list re-sorting — the actual source of truth
    /// after a reload is the file's own modification date (see
    /// `loadAllNotes`), which a coordinated write updates to the same
    /// moment anyway.
    func save(_ note: Note) {
        var updated = note
        updated.modifiedAt = Date()
        if let index = notes.firstIndex(where: { $0.id == updated.id }) {
            notes[index] = updated
        } else {
            notes.append(updated)
        }
        notes.sort { $0.modifiedAt > $1.modifiedAt }
        persist(updated)
    }

    /// Deletes permanently — no trash/undo in v1. Callers (see
    /// `NotesListView`) are expected to confirm with the user first.
    ///
    /// Callers that hold a reference to `note` across an async boundary
    /// (see `NotesEditorView.saveIfStillExists`) must re-check
    /// `notes.contains` before calling `save` again for this id — otherwise
    /// a pending autosave/flush can silently resurrect a note that was just
    /// deleted here.
    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        let directory = currentDirectory
        Task.detached(priority: .utility) {
            do {
                try Self.deleteNoteFile(id: note.id, in: directory)
            } catch {
                notesLog.error("delete failed for \(note.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Persistence (off-main-actor helpers)

    private func persist(_ note: Note) {
        let directory = currentDirectory
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Self.writeNoteFile(note, to: directory)
            } catch {
                notesLog.error("save failed for \(note.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                guard let self else { return }
                await MainActor.run {
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    /// Ubiquity container if iCloud is available and entitled, else the local
    /// fallback directory. Both are created on demand.
    private nonisolated static func resolveStorageDirectory() -> (url: URL, isUsingiCloud: Bool) {
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let dir = container.appendingPathComponent("Documents/Notes", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return (dir, true)
        }
        return (localFallbackDirectory, false)
    }

    private nonisolated static var localFallbackDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Tippi/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One-time move of any locally-fallback-stored notes into the iCloud
    /// container, the first time iCloud becomes available. Guarded by a
    /// UserDefaults flag — but only set once every file in this pass either
    /// migrated successfully or was already present at the destination.
    /// A partial failure (copy error, coordination error) leaves the flag
    /// unset so the *next* `refresh()` retries — safe to retry, since
    /// already-migrated files are skipped via the `fileExists` check below.
    /// The original local file is only ever removed after its copy is
    /// verified to have actually succeeded — never on the strength of a
    /// `try?` alone, which would otherwise delete the only copy of a note
    /// whose copy silently failed.
    private nonisolated static func migrateLocalNotesIfNeeded(into iCloudDirectory: URL) {
        guard !UserDefaults.standard.bool(forKey: migratedDefaultsKey) else { return }

        let localDir = localFallbackDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil) else {
            // Local directory unreadable or doesn't exist — nothing pending to migrate.
            UserDefaults.standard.set(true, forKey: migratedDefaultsKey)
            return
        }

        var allSucceeded = true
        for file in files where file.pathExtension == fileExtension {
            let destination = iCloudDirectory.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }

            var coordinatorError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinatorError) { url in
                do {
                    try FileManager.default.copyItem(at: file, to: url)
                } catch {
                    copyError = error
                }
            }

            if let coordinatorError {
                notesLog.error("migration coordination failed for \(file.lastPathComponent, privacy: .public): \(coordinatorError.localizedDescription, privacy: .public)")
                allSucceeded = false
                continue
            }
            if let copyError {
                notesLog.error("migration copy failed for \(file.lastPathComponent, privacy: .public): \(copyError.localizedDescription, privacy: .public)")
                allSucceeded = false
                continue
            }
            // Copy verified — safe to remove the local original now.
            try? FileManager.default.removeItem(at: file)
            notesLog.notice("migrated \(file.lastPathComponent, privacy: .public) to iCloud")
        }

        if allSucceeded {
            UserDefaults.standard.set(true, forKey: migratedDefaultsKey)
        }
    }

    /// Lists every note file in `directory`. Any ubiquitous item not yet
    /// downloaded locally is skipped this pass (download is kicked off, it
    /// will appear on the next `refresh()`) rather than blocking here.
    private nonisolated static func loadAllNotes(from directory: URL) -> [Note] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]
        ) else {
            return []
        }

        var result: [Note] = []
        for url in entries where url.pathExtension == fileExtension {
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               status != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            if let note = readNoteFile(at: url) {
                result.append(note)
            }
        }
        return result
    }

    // MARK: - File Coordinator wrapped I/O
    //
    // Required for anything inside an iCloud Ubiquity container — reading or
    // writing without a coordinator races the sync daemon and can corrupt or
    // silently drop data.

    /// Only files named `<uuid>.txt` (app-created notes) are recognized —
    /// any other `.txt` dropped into the folder by hand is skipped, not
    /// adopted. (Arbitrary external file adoption is a real possible
    /// follow-up, not part of this scope.)
    private nonisolated static func readNoteFile(at url: URL) -> Note? {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
            notesLog.notice("skipped non-note file \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        var coordinatorError: NSError?
        var content: String?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            content = try? String(contentsOf: coordinatedURL, encoding: .utf8)
        }
        if let coordinatorError {
            notesLog.error("read coordination failed for \(url.lastPathComponent, privacy: .public): \(coordinatorError.localizedDescription, privacy: .public)")
        }
        guard let content else { return nil }

        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = resourceValues?.creationDate ?? Date()
        let modified = resourceValues?.contentModificationDate ?? created
        return Note(id: id, content: content, createdAt: created, modifiedAt: modified)
    }

    private nonisolated static func writeNoteFile(_ note: Note, to directory: URL) throws {
        let url = directory.appendingPathComponent("\(note.id.uuidString).\(fileExtension)")
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                try note.content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    private nonisolated static func deleteNoteFile(id: UUID, in directory: URL) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var coordinatorError: NSError?
        var deleteError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                deleteError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let deleteError { throw deleteError }
    }
}
