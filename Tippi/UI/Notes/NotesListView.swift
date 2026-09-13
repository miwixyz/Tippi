import SwiftUI

/// Note list with new/delete. Deletion always confirms first — permanent,
/// no trash in v1 (agreed feature scope, 2026-09-13).
struct NotesListView: View {
    @ObservedObject var store: NotesStore
    @Binding var selectedNoteID: UUID?
    @State private var noteToDelete: Note?
    // Mirrors `NotesPreferences.favoriteIDs` locally so toggling a star
    // re-renders immediately — the preference itself isn't `@Published`.
    @State private var favoriteIDs: Set<UUID> = NotesPreferences.favoriteIDs

    private var favoriteNotes: [Note] {
        store.notes.filter { favoriteIDs.contains($0.id) }
    }

    private var otherNotes: [Note] {
        store.notes.filter { !favoriteIDs.contains($0.id) }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            // No section headers at all while nothing is starred yet — the
            // common case on first use should look exactly like before.
            if favoriteNotes.isEmpty {
                ForEach(store.notes) { row(for: $0) }
            } else {
                Section(String(localized: "notes.section.favorites")) {
                    ForEach(favoriteNotes) { row(for: $0) }
                }
                Section(String(localized: "notes.section.all")) {
                    ForEach(otherNotes) { row(for: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        // Re-reads on the same trigger `NotesRootView` already refreshes note
        // content on (window appear) — a star set on another Mac shouldn't
        // need a full app relaunch here to catch up, any more than a note's
        // content itself would.
        .onAppear {
            favoriteIDs = NotesPreferences.favoriteIDs
        }
        .toolbar {
            ToolbarItem {
                Button {
                    let note = store.create()
                    selectedNoteID = note.id
                } label: {
                    Label(String(localized: "notes.new"), systemImage: "square.and.pencil")
                }
            }
        }
        .alert(
            String(localized: "notes.delete.confirm.title"),
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { isPresented in if !isPresented { noteToDelete = nil } }
            )
        ) {
            Button(String(localized: "notes.delete.confirm.cancel"), role: .cancel) {
                noteToDelete = nil
            }
            Button(String(localized: "notes.delete.confirm.ok"), role: .destructive) {
                if let note = noteToDelete {
                    if selectedNoteID == note.id { selectedNoteID = nil }
                    store.delete(note)
                }
                noteToDelete = nil
            }
        } message: {
            Text(String(localized: "notes.delete.confirm.body"))
        }
    }

    @ViewBuilder
    private func row(for note: Note) -> some View {
        let isFavorite = favoriteIDs.contains(note.id)
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(note.modifiedAt, format: .relative(presentation: .numeric))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                toggleFavorite(note)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(String(localized: isFavorite ? "notes.unfavorite" : "notes.favorite"))
        }
        .tag(note.id)
        .contextMenu {
            Button {
                toggleFavorite(note)
            } label: {
                Label(
                    String(localized: isFavorite ? "notes.unfavorite" : "notes.favorite"),
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
            Button(role: .destructive) {
                noteToDelete = note
            } label: {
                Label(String(localized: "notes.delete"), systemImage: "trash")
            }
        }
    }

    private func toggleFavorite(_ note: Note) {
        NotesPreferences.toggleFavorite(note.id)
        favoriteIDs = NotesPreferences.favoriteIDs
    }
}
