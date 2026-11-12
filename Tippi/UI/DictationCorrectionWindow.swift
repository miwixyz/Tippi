import AppKit
import SwiftUI

@MainActor
final class DictationCorrectionWindow: NSWindowController, NSWindowDelegate {
    static let shared = DictationCorrectionWindow(window: nil)

    func present(editing rule: DictationCorrections.Rule? = nil) {
        close()
        let editor = DictationCorrectionEditor(original: rule) { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: editor))
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "dictation.corrections.action")
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.center()
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

@MainActor
private struct DictationCorrectionEditor: View {
    @ObservedObject private var corrections = DictationCorrections.shared
    let original: DictationCorrections.Rule?
    let dismiss: () -> Void
    @State private var heard: String
    @State private var replacement: String
    @FocusState private var focusHeard: Bool

    init(original: DictationCorrections.Rule?, dismiss: @escaping () -> Void) {
        self.original = original
        self.dismiss = dismiss
        _heard = State(initialValue: original?.heard ?? "")
        _replacement = State(initialValue: original?.replacement ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if original == nil, let recent = corrections.recent {
                Text("dictation.corrections.last").font(.headline)
                ScrollView {
                    Text(verbatim: recent)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            TextField("dictation.corrections.heard", text: $heard)
                .focused($focusHeard)
            TextField("dictation.corrections.replacement", text: $replacement)
            Text("dictation.corrections.editorHint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "dictation.corrections.cancel"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "dictation.corrections.save")) {
                    if let rule, corrections.save(rule, editing: original) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.map { !corrections.canSave($0, editing: original) } ?? true)
            }
        }
        .padding(20)
        .frame(width: 470)
        .onAppear { focusHeard = true }
        .onChange(of: corrections.recent) { _, _ in
            if original == nil { dismiss() }
        }
    }

    private var rule: DictationCorrections.Rule? {
        .init(heard: heard, replacement: replacement)
    }
}

@MainActor
struct DictationCorrectionsSection: View {
    @ObservedObject private var corrections = DictationCorrections.shared

    var body: some View {
        Section {
            Toggle("dictation.corrections.toggle", isOn: Binding(
                get: { corrections.enabled },
                set: { corrections.setEnabled($0) }
            ))
            Text("dictation.corrections.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(corrections.rules) { rule in
                HStack {
                    Text(verbatim: "\(rule.heard) → \(rule.replacement)")
                    Spacer()
                    Button(String(localized: "dictation.corrections.edit")) {
                        DictationCorrectionWindow.shared.present(editing: rule)
                    }
                    Button(String(localized: "dictation.corrections.remove"), role: .destructive) {
                        corrections.remove(rule)
                    }
                }
            }
        } header: {
            Text("dictation.corrections.title")
        }
    }
}
