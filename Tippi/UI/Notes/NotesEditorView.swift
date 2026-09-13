import AppKit
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
    @State private var isGeneratingTitle = false
    @State private var titleTask: Task<Void, Never>?

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
                titleTask?.cancel()
                flush()
            }

            Divider()

            HStack(spacing: 14) {
                Button {
                    generateTitle()
                } label: {
                    if isGeneratingTitle {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(String(localized: "notes.generateTitle"), systemImage: "sparkles")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "notes.generateTitle"))
                .disabled(isGeneratingTitle || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    exportAsText()
                } label: {
                    Label(String(localized: "notes.export"), systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "notes.export"))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Text(String(format: String(localized: "notes.counter"), wordCount, text.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Notes already live as `.txt` on disk (`iCloud Drive → Tippi → Notes`,
    /// see `NotesStore`) — this is for sending a copy somewhere else
    /// (Desktop, a message, a different folder) without having to know
    /// that path exists. Real request, 2026-09-13.
    private func exportAsText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(note.title).txt"
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            ToastWindowController.shared.show(message: String(localized: "notes.export.failed"))
        }
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Asks Tippi's configured AI provider for a short title and inserts it
    /// as a new first line above the existing content — "insert", not
    /// "replace", per the actual request: nothing the user wrote is
    /// touched. Tracked in `titleTask` and cancelled on `onDisappear` (same
    /// discipline as `saveTask`) so a slow response arriving after the user
    /// has already switched to a different note can never write into the
    /// wrong one — `text`/`note` here are this view's own `@State`, tied to
    /// this specific note via `.id(note.id)` at the call site, but the task
    /// itself keeps running in the background unless explicitly cancelled.
    private func generateTitle() {
        let content = text
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGeneratingTitle = true
        titleTask = Task {
            defer { isGeneratingTitle = false }
            do {
                let result = try await LLMRouter.shared.complete(
                    systemPrompt: """
                    Generate a short, descriptive title (3-6 words) for the following note. \
                    Return ONLY the title itself — no quotes, no trailing punctuation, no \
                    explanation. Write it in the same language as the note.
                    """,
                    userText: content
                )
                guard !Task.isCancelled else { return }
                let title = result.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'—-"))
                guard !title.isEmpty else { return }
                text = "\(title)\n\n\(content)"
            } catch {
                guard !Task.isCancelled else { return }
                ToastWindowController.shared.show(message: String(localized: "notes.generateTitle.failed"))
            }
        }
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
