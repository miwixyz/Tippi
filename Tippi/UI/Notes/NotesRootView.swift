import SwiftUI

/// Split view: note list on the left, editor for the selected note on the
/// right. Refreshes the store on appear — the "refresh on open, not live"
/// sync model agreed for v1 (see `NotesStore`).
struct NotesRootView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var selectedNoteID: UUID?

    var body: some View {
        NavigationSplitView {
            NotesListView(store: store, selectedNoteID: $selectedNoteID)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let id = selectedNoteID, let note = store.notes.first(where: { $0.id == id }) {
                NotesEditorView(store: store, note: note)
                    .id(note.id) // forces the editor's @State to reset when switching notes
            } else {
                ContentUnavailableView(
                    String(localized: "notes.empty.title"),
                    systemImage: "note.text",
                    description: Text(String(localized: "notes.empty.subtitle"))
                )
            }
        }
        .onAppear {
            store.refresh()
            if selectedNoteID == nil {
                selectedNoteID = store.notes.first?.id
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
