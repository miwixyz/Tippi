import SwiftUI

/// Note list with new/delete. Deletion always confirms first — permanent,
/// no trash in v1 (agreed feature scope, 2026-09-13).
struct NotesListView: View {
    @ObservedObject var store: NotesStore
    @Binding var selectedNoteID: UUID?
    @State private var noteToDelete: Note?

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(store.notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.callout)
                        .lineLimit(1)
                    Text(note.modifiedAt, format: .relative(presentation: .numeric))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tag(note.id)
                .contextMenu {
                    Button(role: .destructive) {
                        noteToDelete = note
                    } label: {
                        Label(String(localized: "notes.delete"), systemImage: "trash")
                    }
                }
            }
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
}
