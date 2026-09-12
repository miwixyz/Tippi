import Foundation

/// A single quick note. Content is plain text (v1 minimal scope — no
/// Markdown rendering, no labels, no lock, no version history — see
/// [[02 Projekte/Tippi]] Notes feature scope, 2026-09-13).
///
/// Not `Codable` — each note is persisted as its own plain `.txt` file
/// (see `NotesStore`), so there's nothing here that gets encoded as a unit.
/// `createdAt`/`modifiedAt` are sourced from the file's own filesystem
/// attributes on load; the in-memory values are just an optimistic mirror
/// for immediate UI feedback between a save and the next reload.
struct Note: Identifiable, Equatable {
    let id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), content: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// First non-empty line of the content, used as the list title — same
    /// convention as quicknotes. Falls back to a placeholder for a blank note.
    var title: String {
        let firstLine = content
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "notes.untitled") : trimmed
    }
}
