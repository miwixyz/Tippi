import AppKit
import SwiftUI

/// Schwebendes Fenster ohne Aktivierung — wie die Prompt-Vorschau: Die App, auf die
/// geantwortet wird, behält den Fokus, damit „Einfügen" ins richtige Feld schreibt.
private final class ReplyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ReplyPreviewWindowController {
    private var window: NSWindow?
    private var onCancel: (() -> Void)?

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        var onClose: (() -> Void)?
        func windowWillClose(_ notification: Notification) { onClose?() }
    }
    private let closeDelegate = CloseDelegate()

    var isOpen: Bool { window != nil }

    func show(model: ReplyDraftModel, onInsert: @escaping (String) -> Void,
              onRegenerate: @escaping () -> Void, onCancel: @escaping () -> Void) {
        close()
        self.onCancel = onCancel
        let view = ReplyPreviewView(
            model: model,
            onInsert: { [weak self] text in
                self?.close(cancelled: false)
                onInsert(text)
            },
            onRegenerate: onRegenerate,
            onCancel: { [weak self] in self?.close() }
        )
        let panel = ReplyPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                               styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.contentViewController = NSHostingController(rootView: view)
        panel.title = String(localized: "reply.window.title")
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.center()
        closeDelegate.onClose = { [weak self] in
            guard let self, self.window != nil else { return }
            self.window = nil
            self.onCancel?()
            self.onCancel = nil
        }
        panel.delegate = closeDelegate
        window = panel
        // Nicht NSApp.activate: sonst verliert die Ziel-App ihren Fokus.
        panel.makeKeyAndOrderFront(nil)
    }

    func close(cancelled: Bool = true) {
        let w = window
        window = nil
        if cancelled { onCancel?() }
        onCancel = nil
        w?.orderOut(nil)
    }
}

struct ReplyPreviewView: View {
    @ObservedObject var model: ReplyDraftModel
    let onInsert: (String) -> Void
    let onRegenerate: () -> Void
    let onCancel: () -> Void
    @State private var showContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(model.intent)
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            content
            notices
            contextDisclosure
            footer
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 360)
        .tippiGlass()
    }

    private var header: some View {
        HStack {
            Label(String(localized: model.isMail ? "reply.header.mail" : "reply.header.chat"),
                  systemImage: "arrowshape.turn.up.left")
                .font(.headline)
            Text("Labs")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.2)))
                .foregroundStyle(.orange)
            Spacer()
            Picker("", selection: $model.language) {
                ForEach(ReplyLanguage.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .help(String(localized: "reply.language.help"))
            .onChange(of: model.language) { _, _ in onRegenerate() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "reply.loading")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        case .failed(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button(String(localized: "reply.retry"), action: onRegenerate)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var notices: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "lock").font(.caption).foregroundStyle(.secondary)
        } else if model.contextSource == .none {
            Label(String(localized: "reply.context.none"), systemImage: "text.badge.xmark")
                .font(.caption).foregroundStyle(.secondary)
        }
        if model.hasPlaceholder {
            Label(String(localized: "reply.placeholder"), systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var contextDisclosure: some View {
        if !model.context.isEmpty {
            DisclosureGroup(isExpanded: $showContext) {
                ScrollView {
                    Text(model.context).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            } label: {
                Text(contextLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var contextLabel: String {
        let source = String(localized: model.contextSource == .selection ? "reply.context.selection" : "reply.context.window")
        return String(format: String(localized: "reply.context.used %@ %lld"), source, model.context.count)
    }

    private var footer: some View {
        HStack {
            Button(String(localized: "reply.cancel"), action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(String(localized: "reply.regenerate"), action: onRegenerate)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.phase == .loading)
            Button(String(localized: "reply.insert")) { onInsert(model.text) }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.phase != .ready || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
