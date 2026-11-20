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
/// - iCloud's own same-file conflict handling is outside this store. When a
///   locally edited note meets a different iCloud version with the same UUID,
///   migration keeps the local text as a separately identified conflict copy.
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
    /// Notes iCloud has not uploaded for over a minute. Makes a silently stuck
    /// upload visible — measured 2026-11-20: iCloud Drive had no cellular data
    /// on the iPhone, edits sat there for two days and nothing said so.
    @Published private(set) var pendingUploadCount = 0
    private var uploadWatch: Task<Void, Never>?
    /// Erster `refresh()` ist durch. Vorher ist `notes` leer – wer per Titel sucht (Sprachnotiz „Eingang“),
    /// würde sonst eine zweite Notiz anlegen.
    @Published private(set) var hasLoaded = false

    /// The note currently open in the editor, or `nil`. Set by `NotesEditorView`.
    ///
    /// External changes for this id are **not** written into the list: the
    /// editor holds the text in its own `@State` and autosaves 600 ms after the
    /// last keystroke. Replacing the model underneath a half-typed sentence is
    /// the one way this feature could destroy work that was never anywhere else.
    var noteBeingEdited: UUID?

    /// Set when a change for `noteBeingEdited` arrived and was held back, so the
    /// UI can say so instead of silently keeping a stale version. Cleared on the
    /// next `refresh()`.
    @Published private(set) var heldBackExternalEdit: Bool = false

    private var liveSync: NotesLiveSync?
    /// Last failed write. Shown in the Notes window; cleared by the next
    /// successful write, not by a reload — a reload used to wipe it on the
    /// next window focus, so a failed save was never seen (audit 2026-09-27).
    @Published var loadError: String?

    /// The editor's latest text that the 600 ms debounce has not saved yet.
    /// Written synchronously on quit — ⌘Q within the debounce window lost
    /// the last keystrokes (audit 2026-09-27).
    private var unsavedEdit: (id: UUID, content: String, base: String?)?
    /// Saves queued but not yet finished. The quit-time write may only tidy up
    /// its own predecessor file when nothing else is still writing.
    private var writesInFlight = 0

    /// Resolved during `refresh()` and reused by `save`/`delete` for the rest
    /// of the session, so every mutation doesn't re-resolve the ubiquity
    /// container. A change in iCloud availability is picked up on the next
    /// `refresh()` (i.e. next time the Notes window opens) — consistent with
    /// the "refresh on open, not live" model above.
    private var currentDirectory: URL = NotesStore.localFallbackDirectory
    /// A refresh reads off-actor. Mutations made after it starts must win over
    /// that older disk snapshot, including deletions (which must not reappear).
    private var mutationRevision = 0
    private var noteMutationRevisions: [UUID: Int] = [:]
    private var refreshRevision = 0

    nonisolated static let fileExtension = "txt"

    init(directory: URL? = nil, refreshOnInit: Bool = true) {
        if let directory { currentDirectory = directory }
        // Ohne Laden beim Start (Tests, eigener Ordner) gilt der Speicher als bereit.
        if refreshOnInit { refresh() } else { hasLoaded = true }
    }

    // MARK: - Public API

    /// Re-resolves storage location (iCloud vs. local fallback), migrates
    /// local notes into iCloud the first time it becomes available, and
    /// reloads the list from disk. Call when the Notes window opens.
    func refresh() {
        refreshRevision += 1
        let request = refreshRevision
        let startedAtMutation = mutationRevision
        let pending = pendingWrite
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // Queued writes first: reading the disk while the editor's last
            // save is still in flight would hand back the older version, which
            // the editor now adopts (review 2026-09-27). Not *in* the queue:
            // saves must never wait for a slow iCloud read, ⌘Q would drop them.
            // A rename of this Mac caught halfway can then surface as a
            // conflict copy — an extra note, never a lost one.
            await pending?.value
            let (directory, usingiCloud) = Self.resolveStorageDirectory()
            if usingiCloud {
                Self.migrateLocalNotesIfNeeded(into: directory)
            }
            // Erstellungsdatum aus dem mit TippAI geteilten Index (NoteCreationIndex).
            let disk = Self.loadAllNotesAndPending(from: directory)
            let loaded = NoteCreationIndex.applyingIndex(to: disk.notes, in: directory)
            // Still downloading ≠ deleted: keep what is in memory (audit 2026-11-17, finding 6).
            let stillDownloading = disk.pending.subtracting(loaded.map(\.id))
            await MainActor.run {
                guard self.refreshRevision == request else { return }
                let changed = Set(self.noteMutationRevisions.compactMap { id, revision in
                    revision > startedAtMutation ? id : nil
                })
                let currentIDs = Set(self.notes.map(\.id))
                let mergeCurrent = Self.currentNotesForRefresh(
                    self.notes, from: self.currentDirectory, to: directory, mutatedIDs: changed
                )
                self.currentDirectory = directory
                self.isUsingiCloud = usingiCloud
                self.notes = Self.preferNewer(
                    loaded: loaded, current: mergeCurrent,
                    preservingIDs: changed.union(stillDownloading).intersection(currentIDs),
                    deletedIDs: changed.subtracting(currentIDs)
                )
                    .sorted { $0.modifiedAt > $1.modifiedAt }
                self.heldBackExternalEdit = false
                self.hasLoaded = true
                self.startLiveSync(in: directory, enabled: usingiCloud)
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
        markMutation(note.id)
        persist(note)
        updateCreationIndex(adding: [note.id: note.createdAt])
        return note
    }

    /// Saves an existing note. Bumps `modifiedAt` to now for
    /// immediate, optimistic list re-sorting — the actual source of truth
    /// after a reload is the file's own modification date (see
    /// `loadAllNotes`), which a coordinated write updates to the same
    /// moment anyway.
    ///
    /// `basedOn` is the version the new text was written on top of — the only
    /// version a rename may remove from disk (see `writeNoteFile`). The editor
    /// passes its own; other callers edit the list's current text.
    func save(_ note: Note, basedOn base: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        if unsavedEdit?.id == note.id { unsavedEdit = nil }
        let previousContent = base ?? notes[index].content
        var updated = note
        updated.modifiedAt = Date()
        notes[index] = updated
        notes.sort { $0.modifiedAt > $1.modifiedAt }
        markMutation(updated.id)
        persist(updated, previousContent: previousContent)
    }

    /// Deletes permanently — no trash/undo in v1. Callers (see
    /// `NotesListView`) are expected to confirm with the user first.
    ///
    /// A later stale autosave cannot resurrect it: `save` ignores IDs absent
    /// from the list, and deletion follows every already-queued write.
    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if unsavedEdit?.id == note.id { unsavedEdit = nil }
        markMutation(note.id)
        let directory = currentDirectory
        let previous = pendingWrite
        pendingWrite = Task.detached(priority: .userInitiated) { [weak self] in
            // Deletion is part of the same queue as saves. Otherwise an older
            // queued save can write this note back after its delete completed.
            await previous?.value
            do {
                try Self.deleteNoteFile(id: note.id, in: directory)
                try? NoteCreationIndex.update(in: directory, removing: [note.id])
            } catch {
                notesLog.error("delete failed for \(note.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                guard let self else { return }
                await MainActor.run { self.loadError = error.localizedDescription }
            }
        }
    }

    private func markMutation(_ id: UUID) {
        mutationRevision += 1
        noteMutationRevisions[id] = mutationRevision
    }

    // MARK: - Live sync

    /// Only meaningful inside the ubiquity container — the local fallback
    /// directory has no second writer, so watching it would cost work and
    /// report nothing.
    private func startLiveSync(in directory: URL, enabled: Bool) {
        guard enabled else {
            liveSync?.stop(); liveSync = nil
            uploadWatch?.cancel(); uploadWatch = nil
            pendingUploadCount = 0
            return
        }
        startUploadWatchIfNeeded()
        if liveSync == nil {
            liveSync = NotesLiveSync { [weak self] urls in
                self?.applyExternalChanges(at: urls)
            }
        }
        liveSync?.start(watching: directory)
    }

    /// Re-checks every 30 s. Finishing an upload raises no file event, so
    /// `NotesLiveSync` alone never notices it.
    private func startUploadWatchIfNeeded() {
        guard uploadWatch == nil else { return }
        uploadWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let directory = self?.currentDirectory else { return }
                let count = await Task.detached(priority: .utility) {
                    NotesStore.pendingUploadCount(in: directory, now: Date())
                }.value
                guard !Task.isCancelled, let self else { return }
                if self.pendingUploadCount != count { self.pendingUploadCount = count }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Counts note files iCloud reports as not uploaded and older than
    /// `minimumAge` — a fresh save needs a few seconds and must not flash the
    /// warning. Files outside iCloud report no upload state and never count.
    /// Same rule as TippAI (`NotesStore.pendingUploadCount`), both read this folder.
    nonisolated static func pendingUploadCount(
        in directory: URL,
        now: Date,
        minimumAge: TimeInterval = 60,
        uploadState: (URL) -> (isUploaded: Bool?, modifiedAt: Date?) = NotesStore.uploadState(of:)
    ) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return 0 }
        return files.filter { url in
            guard url.pathExtension == fileExtension else { return false }
            let state = uploadState(url)
            guard state.isUploaded == false else { return false }
            guard let modified = state.modifiedAt else { return true }
            return now.timeIntervalSince(modified) >= minimumAge
        }.count
    }

    nonisolated static func uploadState(of url: URL) -> (isUploaded: Bool?, modifiedAt: Date?) {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .contentModificationDateKey
        ])
        guard values?.isUbiquitousItem == true else { return (nil, values?.contentModificationDate) }
        return (values?.ubiquitousItemIsUploaded, values?.contentModificationDate)
    }

    /// Folds externally changed files into the list. **Upsert only — this never
    /// removes a note**, see `NotesLiveSync` for why absence is not deletion.
    ///
    /// Three guards, each for a case that actually happens:
    /// - the note open in the editor is skipped (see `noteBeingEdited`)
    /// - an older version is ignored, so a late-arriving file cannot undo a
    ///   newer local edit; this is the same `modifiedAt` comparison
    ///   `loadAllNotes` already uses for duplicate files
    /// - a file that no longer parses as a note is skipped rather than dropping
    ///   the in-memory note
    func applyExternalChanges(at urls: [URL]) {
        let incoming = NoteCreationIndex.keepingCreation(of: notes, for: urls.compactMap { Self.readNoteFile(at: $0) })
        guard !incoming.isEmpty else { return }
        let result = Self.merge(incoming, into: notes, skipping: noteBeingEdited)
        notes = result.notes
        if result.heldBack {
            heldBackExternalEdit = true
            notesLog.notice("external change held back: note is open in the editor")
        }
    }

    /// A full reload from disk, except that an in-memory note newer than its
    /// file wins — a save made while the reload ran must not be undone by it.
    /// Notes absent on disk are dropped, as before (deleted on the other Mac).
    nonisolated static func preferNewer(
        loaded: [Note], current: [Note],
        preservingIDs: Set<UUID> = [], deletedIDs: Set<UUID> = []
    ) -> [Note] {
        var result = loaded.filter { !deletedIDs.contains($0.id) }.map { disk in
            if let mine = current.first(where: { $0.id == disk.id }), mine.modifiedAt > disk.modifiedAt {
                return mine
            }
            return disk
        }
        for mine in current where preservingIDs.contains(mine.id) {
            if let index = result.firstIndex(where: { $0.id == mine.id }) {
                result[index] = mine
            } else {
                result.append(mine)
            }
        }
        return result
    }

    /// The merge decision, pulled out of `applyExternalChanges` so it can be
    /// tested without a store, a directory or iCloud. `NotesStore` is a
    /// singleton over the real container — a test that drove it would read
    /// Michael's actual notes, which is the kind of measurement that changes
    /// the machine it runs on.
    ///
    /// Returns the new list and whether anything was withheld because it is
    /// open in the editor.
    nonisolated static func merge(
        _ incoming: [Note],
        into existing: [Note],
        skipping editedID: UUID?
    ) -> (notes: [Note], heldBack: Bool) {
        var result = existing
        var heldBack = false

        for note in incoming {
            if note.id == editedID {
                heldBack = true
                continue
            }
            if let index = result.firstIndex(where: { $0.id == note.id }) {
                // An older version must never undo a newer local edit — same
                // `modifiedAt` comparison `loadAllNotes` uses for duplicates.
                guard note.modifiedAt > result[index].modifiedAt else { continue }
                result[index] = note
            } else {
                result.append(note)
            }
        }

        result.sort { $0.modifiedAt > $1.modifiedAt }
        return (result, heldBack)
    }

    // MARK: - Persistence (off-main-actor helpers)

    /// Serialises every write so two saves of the same note cannot interleave.
    ///
    /// `writeNoteFile` writes `<title> — <uuid>.txt` and then deletes every
    /// other file carrying the same UUID. Two unsynchronised `Task.detached`
    /// blocks could therefore run W1 → W2 → S1 → S2: S1 deletes the file W2
    /// just wrote, S2 deletes the one W1 wrote, and the note is gone from disk
    /// entirely — it survives only in memory until the next save, which after
    /// a window close may never come. Renaming (editing the first line) is
    /// exactly when two saves land close together, so this is not a rare
    /// interleaving. Found by audit 2026-09-19.
    ///
    /// Chaining onto the previous task keeps writes in submission order at the
    /// cost of nothing measurable — these are single small text files, and the
    /// work still runs off the main actor.
    private var pendingWrite: Task<Void, Never>?

    /// Called by the editor on every change until the debounce saves it.
    func noteUnsavedEdit(id: UUID, content: String, basedOn base: String? = nil) {
        unsavedEdit = (id, content, base)
    }

    /// Synchronous last write for `applicationWillTerminate` — an async write
    /// would not finish before the process exits.
    func flushUnsavedEditSynchronously() {
        guard let edit = unsavedEdit,
              var note = notes.first(where: { $0.id == edit.id }),
              note.content != edit.content else { return }
        note.content = edit.content
        note.modifiedAt = Date()
        do {
            // Pruning only when no queued async write is still running: two
            // interleaved writes with different titles could each act on the
            // other's file (review 2026-09-27). Without pruning, a title changed
            // just before ⌘Q leaves the old file behind, which the next load
            // keeps as a conflict copy — an extra note, not a lost one.
            try Self.writeNoteFile(note, to: currentDirectory, pruneStale: writesInFlight == 0,
                                   previousContent: edit.base)
            unsavedEdit = nil
        } catch {
            notesLog.error("final save on quit failed for \(note.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist(_ note: Note, previousContent: String? = nil) {
        let directory = currentDirectory
        let previous = pendingWrite
        writesInFlight += 1
        pendingWrite = Task.detached(priority: .userInitiated) { [weak self] in
            await previous?.value
            var failure: String?
            do {
                try Self.writeNoteFile(note, to: directory, previousContent: previousContent)
            } catch {
                notesLog.error("save failed for \(note.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failure = error.localizedDescription
            }
            guard let self else { return }
            let message = failure
            await MainActor.run {
                self.writesInFlight -= 1
                self.loadError = message
            }
        }
    }

    /// Ubiquity container if iCloud is available and entitled, else the local
    /// fallback directory. Both are created on demand.
    private nonisolated static func resolveStorageDirectory() -> (url: URL, isUsingiCloud: Bool) {
        // Bild-Testkopie: nie in den iCloud-Container `iCloud~dev~mwlr~Tippi` (BildKopie).
        if !BildKopie.isActive, let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let dir = container.appendingPathComponent("Documents/Notes", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return (dir, true)
        }
        return (localFallbackDirectory, false)
    }

    private nonisolated static var localFallbackDirectory: URL {
        let dir = BildKopie.applicationSupport.appendingPathComponent("Tippi/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Moves notes from the local fallback folder into the iCloud container on
    /// **every** refresh with iCloud available — not once. The old one-time
    /// flag stranded every note written locally later (iCloud off for a while,
    /// or a note created before the first refresh resolved the container):
    /// invisible in the app, sitting in Application Support (audit
    /// 2026-09-27). Cheap: one directory listing, empty in the normal case.
    /// If iCloud already has the same UUID with different content, both
    /// versions survive: the offline version gets a new UUID as a conflict copy.
    /// The original local file is only ever removed after its copy is
    /// verified to have actually succeeded — never on the strength of a
    /// `try?` alone, which would otherwise delete the only copy of a note
    /// whose copy silently failed.
    private nonisolated static func migrateLocalNotesIfNeeded(into iCloudDirectory: URL) {
        migrateLocalNotesIfNeeded(from: localFallbackDirectory, into: iCloudDirectory)
    }

    /// Directory-injected seam keeps migration tests away from the real iCloud
    /// container and the user's actual notes.
    nonisolated static func migrateLocalNotesIfNeeded(from localDir: URL, into iCloudDirectory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil) else {
            return  // local directory unreadable or absent — nothing to migrate
        }
        guard var cloudFiles = try? FileManager.default.contentsOfDirectory(
            at: iCloudDirectory, includingPropertiesForKeys: nil
        ) else {
            notesLog.error("migration cannot list iCloud notes — leaving local copies untouched")
            return
        }

        for file in files where file.pathExtension == fileExtension {
            guard let id = uuidSuffix(of: file.deletingPathExtension().lastPathComponent) else { continue }
            let sameID = cloudFiles.filter { cloudNoteID(in: $0) == id }
            if !sameID.isEmpty {
                guard let localContent = try? String(contentsOf: file, encoding: .utf8) else {
                    notesLog.error("migration cannot read local note \(file.lastPathComponent, privacy: .private)")
                    continue
                }
                if !sameID.contains(where: { $0.pathExtension == "icloud" }),
                   sameID.contains(where: { $0.pathExtension == fileExtension && readNoteFile(at: $0)?.content == localContent }) {
                    // Same text already reached iCloud; the local file is only a
                    // duplicate and can be removed without losing a version.
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                let conflict = Note(content: localContent)
                do {
                    try writeNoteFile(conflict, to: iCloudDirectory)
                    cloudFiles.append(iCloudDirectory.appendingPathComponent(filename(for: conflict)))
                    try FileManager.default.removeItem(at: file)
                    notesLog.notice("kept offline note as an iCloud conflict copy")
                } catch {
                    notesLog.error("migration conflict copy failed — local file retained: \(error.localizedDescription, privacy: .public)")
                }
                continue
            }

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
                notesLog.error("migration coordination failed for \(file.lastPathComponent, privacy: .private): \(coordinatorError.localizedDescription, privacy: .public)")
                continue
            }
            if let copyError {
                notesLog.error("migration copy failed for \(file.lastPathComponent, privacy: .private): \(copyError.localizedDescription, privacy: .public)")
                continue
            }
            // Copy verified — safe to remove the local original now.
            cloudFiles.append(destination)
            try? FileManager.default.removeItem(at: file)
            notesLog.notice("migrated \(file.lastPathComponent, privacy: .private) to iCloud")
        }
    }

    /// Recognises both downloaded notes and iCloud's `.name.txt.icloud`
    /// placeholders without reading or downloading the latter. A placeholder
    /// with the same UUID forces a separate conflict copy so the local text is
    /// visible immediately without overwriting an unseen cloud version.
    nonisolated static func cloudNoteID(in url: URL) -> UUID? {
        var name = url.lastPathComponent
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            name.removeFirst()
            name.removeLast(".icloud".count)
        }
        guard name.hasSuffix(".txt") else { return nil }
        return uuidSuffix(of: String(name.dropLast(".txt".count)))
    }

    // `loadAllNotes` and the conflict copies: NotesStore+Duplicates.swift

    // MARK: - File Coordinator wrapped I/O
    //
    // Required for anything inside an iCloud Ubiquity container — reading or
    // writing without a coordinator races the sync daemon and can corrupt or
    // silently drop data.

    /// Filenames are `<title> — <uuid>.txt` once a note has a first line, or
    /// plain `<uuid>.txt` before that — so identity is always recoverable by
    /// pulling the trailing 36-character UUID off the stem, regardless of
    /// whatever human-readable title currently precedes it. Any other `.txt`
    /// dropped into the folder by hand (no parseable trailing UUID) is
    /// skipped, not adopted. (Arbitrary external file adoption is a real
    /// possible follow-up, not part of this scope.)
    nonisolated static func readNoteFile(at url: URL) -> Note? {
        guard let id = uuidSuffix(of: url.deletingPathExtension().lastPathComponent) else {
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

    /// Writes under a filename that reflects the note's current title (its
    /// first line) — real request, 2026-09-13: notes visible in Finder
    /// (`iCloud Drive → Tippi → Notes`, see v2.4.1) must show a readable name,
    /// not a bare UUID. Every write recomputes the desired name and only
    /// actually renames on disk when it changed since the last save — which
    /// only happens when the first line itself changed, not on every
    /// keystroke elsewhere in the note.
    ///
    /// `previousContent` is what this Mac last had for the note. Only a file
    /// holding exactly that (or the new text) is this Mac's own predecessor and
    /// may go. Any other file with the same UUID came from another Mac — e.g.
    /// its own rename, held back while the note was open here — and is kept as
    /// a conflict copy instead of being deleted unseen (audit 2026-11-17).
    nonisolated static func writeNoteFile(
        _ note: Note, to directory: URL, pruneStale: Bool = true, previousContent: String? = nil
    ) throws {
        let newURL = directory.appendingPathComponent(filename(for: note))
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: newURL, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                try note.content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }

        // The title changed (or was just added) since the last write — the
        // file(s) under any previous name are now stale duplicates of this
        // same note (same UUID suffix). Only removed after the new name's
        // write is confirmed above, so a failure never leaves zero copies on
        // disk. Deletes every match, not just one, and explicitly excludes
        // `newURL` itself — real bug found 2026-09-13: the old lookup
        // ("first entry whose name ends in this UUID") could
        // non-deterministically return the file that was just written above
        // (its own name also ends in the same UUID+extension), since
        // `contentsOfDirectory` order isn't guaranteed. That silently
        // skipped the delete and left the actual old file orphaned on disk
        // forever, later re-appearing as a ghost duplicate of the same note
        // (self-healed for already-affected installs in `loadAllNotes`).
        for staleURL in pruneStale ? staleFileURLs(forID: note.id, in: directory, excluding: newURL.lastPathComponent) : [] {
            // Unreadable (still downloading, coordination failed): not known
            // to be ours — leave it for the next load instead of guessing.
            guard let stale = readNoteFile(at: staleURL) else { continue }
            if stale.content == note.content || stale.content == previousContent {
                try? deleteFile(at: staleURL)
            } else {
                _ = keepAsConflictCopy(stale, at: staleURL, in: directory)
            }
        }
    }

    /// Deletes every file matching this note's ID — normally exactly one,
    /// but defensively cleans up all of them in case a stale duplicate (see
    /// `writeNoteFile`) is still sitting around. Best-effort: keeps trying
    /// remaining matches even if one fails, so a single locked/coordinated
    /// file never leaves the rest behind.
    private nonisolated static func deleteNoteFile(id: UUID, in directory: URL) throws {
        let urls = staleFileURLs(forID: id, in: directory, excluding: nil)
        guard !urls.isEmpty else { return }
        var lastError: Error?
        for url in urls {
            do {
                try deleteFile(at: url)
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
    }

    nonisolated static func deleteFile(at url: URL) throws {
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

    // MARK: - Filename ↔ UUID

    /// A UUID string is always exactly 36 characters — pulling the suffix
    /// works whether the stem is a bare UUID or `<title> — <uuid>`.
    private nonisolated static func uuidSuffix(of stem: String) -> UUID? {
        guard stem.count >= 36 else { return nil }
        return UUID(uuidString: String(stem.suffix(36)))
    }

    /// `<uuid>.txt` for a note with no first line yet; `<title> — <uuid>.txt`
    /// once it has one. Deliberately not `Note.title` (that returns a
    /// localized "Untitled" placeholder for display) — an empty first line
    /// here means "no title yet", so the plain-UUID form is used instead of
    /// baking a locale-specific placeholder string into a filename.
    private nonisolated static func filename(for note: Note) -> String {
        let firstLine = note.content
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let title = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "\(note.id.uuidString).\(fileExtension)" }

        // "/" is POSIX-illegal in a filename; ":" is legacy-illegal in Finder
        // (HFS+ path separator) and still worth avoiding.
        let sanitized = title
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else { return "\(note.id.uuidString).\(fileExtension)" }

        // Keep the visible part short — Finder listings with an 80+ char
        // title are unreadable anyway. Also bounded in UTF-16 units: APFS
        // allows 255 of those per name, and 80 *characters* of flag or ZWJ
        // emoji exceed it — every save of such a note failed (measured,
        // audit 2026-09-27). 180 leaves room for " — <UUID>.txt" (43).
        var truncated = String(sanitized.prefix(80))
        while truncated.utf16.count > 180 { truncated.removeLast() }
        return "\(truncated) — \(note.id.uuidString).\(fileExtension)"
    }

    /// Every file in `directory` whose stem ends in this note's UUID —
    /// normally exactly one, but can legitimately return more than one for
    /// the reasons documented at both call sites (a stale rename leftover,
    /// or the file just written by the caller itself, which `excludedFilename`
    /// lets callers exclude explicitly rather than relying on "first match"
    /// — the bug this replaced).
    private nonisolated static func staleFileURLs(forID id: UUID, in directory: URL, excluding excludedFilename: String?) -> [URL] {
        let suffix = "\(id.uuidString).\(fileExtension)"
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.filter { $0.lastPathComponent.hasSuffix(suffix) && $0.lastPathComponent != excludedFilename }
    }
}

extension NotesStore {
    /// After switching local → iCloud, the old in-memory note must not win
    /// over the iCloud original merely because its local mtime is newer: its
    /// text has already become a separate conflict copy during migration.
    /// Only edits made while this very refresh was running remain in memory.
    nonisolated static func currentNotesForRefresh(
        _ current: [Note], from oldDirectory: URL, to newDirectory: URL,
        mutatedIDs: Set<UUID>
    ) -> [Note] {
        guard oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL else { return current }
        return current.filter { mutatedIDs.contains($0.id) }
    }
}

// Eigene Erweiterung, damit der Klassenrumpf unter der Lint-Grenze bleibt; im selben File,
// weil sie die private Schreibwarteschlange braucht.
extension NotesStore {
    /// Allows isolated directory tests to observe the whole save/delete queue.
    func waitForPendingOperations() async {
        await pendingWrite?.value
    }

    /// Erstellungsdatum festhalten bzw. entfernen, hinter allen laufenden Schreibvorgängen.
    /// Scheitert es, trägt der nächste Ladevorgang das Datei-Datum nach — kein Hinweis nötig.
    fileprivate func updateCreationIndex(adding: [UUID: Date] = [:], removing: Set<UUID> = []) {
        let directory = currentDirectory
        let previous = pendingWrite
        pendingWrite = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try NoteCreationIndex.update(in: directory, adding: adding, removing: removing)
            } catch {
                notesLog.error("creation index update failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
