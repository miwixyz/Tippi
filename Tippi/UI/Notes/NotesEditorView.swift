import SwiftUI

/// Plain-text editor for one note (v1 minimal scope — no Markdown rendering).
/// Pasting anything with formatting (email, web text, a styled document)
/// lands as clean text automatically, with a quiet toast confirming it —
/// see `PlainTextEditor`. Autosaves ~600 ms after the user stops typing, and
/// flushes immediately when the view disappears (note switched, window
/// closed) so the last few keystrokes are never lost to the debounce window.
struct NotesEditorView: View {
    @ObservedObject var store: NotesStore
    let note: Note
    @State private var text: String
    @State private var saveTask: Task<Void, Never>?

    init(store: NotesStore, note: Note) {
        self.store = store
        self.note = note
        _text = State(initialValue: note.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlainTextEditor(text: $text, onPasteStrippedFormatting: {
                ToastWindowController.shared.show(message: String(localized: "notes.formattingRemoved"))
            })
            .onChange(of: text) { _, newValue in
                scheduleSave(newValue)
            }
            .onDisappear {
                saveTask?.cancel()
                flush()
            }

            Divider()

            HStack {
                Text(String(format: String(localized: "notes.counter"), wordCount, text.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Saves are always gated on the note still existing in the store —
    /// without this, deleting the note currently open in the editor
    /// resurrects it: `store.delete` removes it synchronously, SwiftUI then
    /// tears this view down, `onDisappear` fires `flush()`, and
    /// `NotesStore.save` would otherwise happily re-append a note whose id
    /// it no longer recognizes as removed.
    private func scheduleSave(_ newValue: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveIfStillExists(content: newValue)
        }
    }

    private func flush() {
        saveIfStillExists(content: text)
    }

    private func saveIfStillExists(content: String) {
        guard store.notes.contains(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.content = content
        store.save(updated)
    }
}
