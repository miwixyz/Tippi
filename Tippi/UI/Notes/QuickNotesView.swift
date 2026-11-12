import AppKit
import SwiftUI

/// Up to three notes as tabs, shown in a popover under the menu bar icon
/// (Michael, 2026-11-09: „in der Menüleiste immer drei feste Notizen“).
/// The notes are ordinary Tippi notes marked in the Notes list, so the editor
/// is the same `NotesEditorView` — same autosave, same iCloud sync.
struct QuickNotesView: View {
    @ObservedObject var store: NotesStore
    let noteIDs: [UUID]
    var onOpenInNotes: (UUID) -> Void
    var onShowMenu: () -> Void
    @State private var selectedID: UUID?
    @State private var size: CGSize = NotesPreferences.quickNotesSize
    @State private var dragStartSize: CGSize?

    private var notes: [Note] {
        NotesPreferences.quickNotes(ids: noteIDs, in: store.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            if notes.count > 1 {
                Picker("", selection: $selectedID) {
                    ForEach(notes) { note in
                        Text(Self.tabTitle(note.title)).tag(Optional(note.id))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .tippiGlass()
                Divider()
            }

            // Content layer: calm, opaque text surface like the Notes window — glass
            // only on the bars around it (Tippi design rule G1 / Apple HIG; Michael
            // chose this after a fully glassed panel read as a grey slab, 2026-11-09).
            Group {
                if let note = notes.first(where: { $0.id == selectedID }) ?? notes.first {
                    NotesEditorView(store: store, note: note)
                        .id(note.id) // fresh editor state per tab, like NotesRootView
                } else {
                    // All marked notes deleted while the panel was open.
                    ContentUnavailableView(
                        String(localized: "notes.empty.title"),
                        systemImage: "note.text"
                    )
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Button(String(localized: "quicknotes.openInNotes")) {
                    if let id = selectedID ?? notes.first?.id { onOpenInNotes(id) }
                }
                .buttonStyle(.link)
                Spacer()
                Button(action: onShowMenu) {
                    Label(String(localized: "quicknotes.showMenu"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "quicknotes.showMenu"))
                .accessibilityLabel(Text(String(localized: "quicknotes.showMenu")))
                resizeGrip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .tippiGlass()
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
        .onAppear {
            if selectedID == nil { selectedID = QuickNotesPopoverController.lastSelectedID ?? notes.first?.id }
            if !notes.contains(where: { $0.id == selectedID }) { selectedID = notes.first?.id }
        }
        .onChange(of: selectedID) { _, id in QuickNotesPopoverController.lastSelectedID = id }
    }

    /// A popover has no window edge to drag (Michael, 2026-11-09: „ein bisschen klein,
    /// muss vergrößerbar sein“) — this grip resizes it; the size is kept for next time.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help(String(localized: "quicknotes.resize"))
            .accessibilityLabel(Text(String(localized: "quicknotes.resize")))
            .onHover { inside in
                if inside {
                    NSCursor.frameResize(position: .bottomRight, directions: .all).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartSize ?? size
                        dragStartSize = start
                        // The popover stays centred under the icon, so it grows to both
                        // sides: double the horizontal drag keeps the grip under the pointer.
                        size = NotesPreferences.clampedQuickNotesSize(CGSize(
                            width: start.width + value.translation.width * 2,
                            height: start.height + value.translation.height))
                    }
                    .onEnded { _ in
                        dragStartSize = nil
                        NotesPreferences.quickNotesSize = size
                    }
            )
    }

    /// Segments share the popover width — a long first line would squeeze the
    /// other tabs, so titles are cut here.
    nonisolated static func tabTitle(_ title: String, limit: Int = 16) -> String {
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Borderless panel that can take keystrokes without activating Tippi — the
/// same pattern as `TranslateQuickPanel`.
private final class QuickNotesPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    /// Esc closes, like a popover.
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// Owns the glass panel under the menu bar icon. Kept out of `AppDelegate`,
/// which already carries the whole menu.
@MainActor
final class QuickNotesPopoverController {
    /// Tab shown last — reopening lands on it again (this session only).
    static var lastSelectedID: UUID?

    var onOpenInNotes: (UUID) -> Void = { _ in }
    var onShowMenu: () -> Void = {}

    private var panel: QuickNotesPanel?
    private var observers: [NSObjectProtocol] = []
    private var globalMouseMonitor: Any?
    /// Top edge and horizontal centre, pinned at open: the panel grows down and
    /// to both sides when resized, never away from the icon.
    private var anchor: NSPoint?
    /// Closing on resign-key can race the status icon's own click — without
    /// this the icon would reopen the panel right after closing it.
    private var lastClose = Date.distantPast

    var isShown: Bool { panel != nil }

    /// Opens or closes the panel. Returns `false` when no quick note is
    /// marked — then the caller shows the regular menu instead.
    func toggle(relativeTo button: NSStatusBarButton) -> Bool {
        if panel != nil {
            close()
            return true
        }
        if Date().timeIntervalSince(lastClose) < 0.3 { return true }
        return open(relativeTo: button)
    }

    /// Opens the panel, never closes it — for `tippi://schnellnotiz`, so a
    /// repeated call cannot make it flicker. Returns `false` when no quick
    /// note is marked, like `toggle`.
    func open(relativeTo button: NSStatusBarButton) -> Bool {
        if panel != nil { return true }
        let store = NotesStore.shared
        let ids = NotesPreferences.quickNoteIDs
        guard !NotesPreferences.quickNotes(ids: ids, in: store.notes).isEmpty,
              let buttonWindow = button.window else { return false }

        let view = QuickNotesView(
            store: store,
            noteIDs: ids,
            onOpenInNotes: { [weak self] id in
                self?.close()
                self?.onOpenInNotes(id)
            },
            onShowMenu: { [weak self] in
                self?.close()
                DispatchQueue.main.async { self?.onShowMenu() }
            }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = QuickNotesPanel(
            contentRect: NSRect(origin: .zero, size: NotesPreferences.quickNotesSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        // The bars' glass can only sample the screen if nothing opaque sits between
        // (same fix as ClickableHostingView, 2026-09-14).
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.isOpaque = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.appearance = AppearanceSettings.panelAppearance()
        panel.onCancel = { [weak self] in self?.close() }

        let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchor = NSPoint(x: iconFrame.midX, y: iconFrame.minY - 6)
        self.panel = panel
        place(panel)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                self.place(panel)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
        // Clicks into other apps — same mechanism as TranslateQuickPanel.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        panel.makeKeyAndOrderFront(nil)
        return true
    }

    /// Centred under the icon, top edge fixed, kept on the icon's screen.
    private func place(_ panel: NSPanel) {
        guard let anchor else { return }
        let size = panel.frame.size
        var x = anchor.x - size.width / 2
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        let origin = NSPoint(x: x.rounded(), y: (anchor.y - size.height).rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    func close() {
        guard let panel else { return }
        lastClose = Date()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        self.panel = nil
        anchor = nil
        panel.orderOut(nil)
        // Tears the SwiftUI tree down so the editor's onDisappear saves the last
        // keystrokes now.
        panel.contentViewController = nil
    }
}
