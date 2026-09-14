import AppKit
import SwiftUI

/// Split view: note list on the left, editor for the selected note on the
/// right. Refreshes the store on appear — the "refresh on open, not live"
/// sync model agreed for v1 (see `NotesStore`).
struct NotesRootView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var selectedNoteID: UUID?
    @State private var isPinned: Bool = NotesPreferences.isPinned

    /// Applies the actual AppKit-level pin (window level + collection
    /// behavior) — this view only owns the toolbar icon's on/off state.
    var onTogglePin: () -> Void = {}

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
        .tippiGlass()
        // Without this the toolbar paints its own opaque strip across the full
        // window width, which sits visibly on top of the glass below it — the
        // "seam" seen on 2026-09-13. Hiding the titlebar chrome alone (see
        // NotesWindowController) is only half the fix; the toolbar backdrop has
        // to go with it, otherwise the edge just moves down a few points.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // `changeFont(_:)` only reaches the text view via the
                    // responder chain if it's already first responder at the
                    // moment a font gets picked in the panel. Clicking this
                    // toolbar button is very often the very first thing a
                    // user does after opening a note — the editor was never
                    // clicked into, so it was never first responder, and the
                    // font choice silently went nowhere. Real bug report,
                    // 2026-09-13: "Die Schriftarten werden nicht übernommen."
                    // Forcing focus onto the editor's text view here, right
                    // before the panel opens, makes it work regardless of
                    // whatever had focus a moment ago.
                    if let window = NSApp.keyWindow,
                       let textView = window.contentView?.firstDescendant(ofType: PlainTextEditor.PasteAwareTextView.self) {
                        window.makeFirstResponder(textView)
                    }
                    NSFontManager.shared.orderFrontFontPanel(nil)
                } label: {
                    Label(String(localized: "notes.font.choose"), systemImage: "textformat")
                }
                .help(String(localized: "notes.font.choose"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPinned.toggle()
                    onTogglePin()
                } label: {
                    Label(pinLabel, systemImage: isPinned ? "pin.fill" : "pin")
                }
                .help(pinLabel)
            }
        }
    }

    private var pinLabel: String {
        String(localized: isPinned ? "notes.pin.unpin" : "notes.pin.pin")
    }
}
