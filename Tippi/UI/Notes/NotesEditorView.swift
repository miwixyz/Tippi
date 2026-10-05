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
    /// The content as last written to (or loaded from) the store. `text` differs
    /// from it only while the user has unsaved edits. Without it, leaving a note
    /// saved the editor's copy unconditionally — stale text over a newer version
    /// from the other Mac, stamped "now", gone on both (audit 2026-09-27).
    @State private var lastSavedText: String
    @State private var saveTask: Task<Void, Never>?
    @State private var isGeneratingTitle = false
    @State private var titleTask: Task<Void, Never>?

    init(store: NotesStore, note: Note) {
        self.store = store
        self.note = note
        _text = State(initialValue: note.content)
        _lastSavedText = State(initialValue: note.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlainTextEditor(text: $text, onPasteStrippedFormatting: {
                ToastWindowController.shared.show(message: String(localized: "notes.formattingRemoved"))
            })
            .onChange(of: text) { _, newValue in
                scheduleSave(newValue)
            }
            // `note` is re-read from the store on every change, but `.id(note.id)`
            // keeps this view's @State — so a newer version from the other Mac
            // (via refresh on window focus) never reached the editor. Adopt it
            // when there is nothing unsaved here; with unsaved edits the local
            // text wins, as before.
            .onChange(of: note.content) { _, external in
                if let adopted = Self.adoptedText(external: external, text: text, lastSaved: lastSavedText) {
                    text = adopted
                    lastSavedText = adopted
                }
            }
            .onAppear {
                // Tells the store to hold back external changes for this note
                // while it is being typed in — the text lives in this view's
                // own @State and autosaves 600 ms after the last keystroke, so
                // replacing the model underneath would discard work that exists
                // nowhere else yet. See NotesStore.noteBeingEdited.
                store.noteBeingEdited = note.id
            }
            .onDisappear {
                saveTask?.cancel()
                titleTask?.cancel()
                flush()
                // Only release the claim if it is still ours: switching notes
                // can run the new view's onAppear before this onDisappear, and
                // clearing unconditionally would unguard the note just opened.
                if store.noteBeingEdited == note.id { store.noteBeingEdited = nil }
                // The held-back change was skipped by live sync, not queued —
                // reload so "applied once you leave this note" actually happens.
                if store.heldBackExternalEdit { store.refresh() }
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
                .disabled(isGeneratingTitle || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                // After `.disabled`: a tooltip inside the disabled scope never
                // shows, and on an empty note the button is disabled.
                .help(String(localized: "notes.generateTitle"))

                Button {
                    exportAsText()
                } label: {
                    Label(String(localized: "notes.export"), systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(String(localized: "notes.export"))

                // Without this the held-back change is invisible: the list shows
                // a version the other Mac has already moved past, and nothing
                // says so. Silently keeping the stale one is the failure mode
                // this whole feature exists to remove.
                if let saveError = store.loadError {
                    Label(String(format: String(localized: "notes.saveFailed"), saveError),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .help(saveError)
                }

                if store.heldBackExternalEdit {
                    Label(String(localized: "notes.externalChangeHeld"), systemImage: "arrow.triangle.2.circlepath")
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                        .help(String(localized: "notes.externalChangeHeld"))
                }

                Spacer()

                Text(String(format: String(localized: "notes.counter"), wordCount, text.count, lineCount))
                    .font(FamilyTheme.font(.caption))
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

    /// Lines as an editor counts them: an empty note has 0, otherwise every
    /// line break starts a new line — a trailing break counts, because the
    /// cursor already sits on that next line (Michael, 2026-10-05).
    private var lineCount: Int {
        text.isEmpty ? 0 : text.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
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
                // Current `text`, not the snapshot sent to the model: anything
                // typed while the request ran must survive.
                text = "\(title)\n\n\(text)"
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
        if newValue != lastSavedText { store.noteUnsavedEdit(id: note.id, content: newValue) }
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

    /// Only writes real edits: a save stamps `modifiedAt = now`, so writing an
    /// unchanged copy would make it "newest" and overwrite the other Mac's edit.
    private func saveIfStillExists(content: String) {
        guard content != lastSavedText else { return }
        guard store.notes.contains(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.content = content
        store.save(updated)
        lastSavedText = content
    }

    /// The external version to show in the editor, or `nil` to keep the
    /// editor's text: unsaved local edits always win, and an unchanged
    /// external value is no news.
    nonisolated static func adoptedText(external: String, text: String, lastSaved: String) -> String? {
        guard text == lastSaved, external != text else { return nil }
        return external
    }
}
