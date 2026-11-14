import AppKit
import SwiftUI
import os

/// Messpunkt Sprachnotiz (Michael 14.11.: „Fenster geht sofort wieder zu“) – nur Zustände, nie Text.
let quickNotesLog = Logger(subsystem: "com.tippi.app", category: "quick-notes")

/// Up to three notes as tabs, shown in a popover under the menu bar icon
/// (Michael, 2026-11-09: „in der Menüleiste immer drei feste Notizen“).
/// The notes are ordinary Tippi notes marked in the Notes list, so the editor
/// is the same `NotesEditorView` — same autosave, same iCloud sync.
struct QuickNotesView: View {
    @ObservedObject var store: NotesStore
    let noteIDs: [UUID]
    var onOpenInNotes: (UUID) -> Void
    var onShowMenu: () -> Void
    /// Deckkraft-Regler (Sprachnotiz, Michael 2026-11-14): der Controller setzt `alphaValue` des Panels.
    var onOpacityChange: (Double) -> Void = { _ in }
    @State private var opacity = NotesSettings.quickNotesOpacity
    @State private var selectedID: UUID?
    @State private var size: CGSize = NotesPreferences.quickNotesSize
    @State private var dragStartSize: CGSize?

    private var notes: [Note] {
        NotesPreferences.quickNotes(ids: noteIDs, in: store.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            if notes.count > 1 {
                // Gleitende Pille statt Segment-Umschalter (Porter-Optik, 13.11.2026).
                SlidingPicker(notes.map { Optional($0.id) }, selection: $selectedID) { id, selected in
                    Text(Self.tabTitle(notes.first { $0.id == id }?.title ?? ""))
                        .font(FamilyTheme.font(12, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                }
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
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $opacity, in: NotesSettings.opacityRange)
                    .controlSize(.mini)
                    .frame(width: 70)
                    .help(String(localized: "quicknotes.opacity"))
                    .accessibilityLabel(Text(String(localized: "quicknotes.opacity")))
                    .onChange(of: opacity) { _, value in
                        NotesSettings.quickNotesOpacity = value
                        onOpacityChange(NotesSettings.quickNotesOpacity)
                    }
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
    /// Schwebe-Modus (Sprachnotiz): bleibt bei Klicks daneben offen und lässt sich verschieben.
    private(set) var isFloating = false
    /// Einmal verschoben → nicht mehr unter das Symbol zurückrücken.
    private var userMoved = false

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
        guard let buttonWindow = button.window else { return false }
        let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return present(ids: NotesPreferences.quickNoteIDs, anchor: NSPoint(x: iconFrame.midX, y: iconFrame.minY - 6),
                       floating: false)
    }

    /// Sprachnotiz (⌃⌥⌘N): Panel schwebend zeigen, mit `focus` („Eingang“) als Reiter – auch wenn die Notiz
    /// keine der drei Schnellnotizen ist. Ohne Menüleisten-Symbol oben mittig auf dem Bildschirm mit der Maus.
    @discardableResult
    func openFloating(relativeTo button: NSStatusBarButton?, focus noteID: UUID?) -> Bool {
        if panel != nil { return true }
        var ids = NotesPreferences.quickNoteIDs
        if let noteID {
            if !ids.contains(noteID) { ids.append(noteID) }
            Self.lastSelectedID = noteID
        }
        let anchor: NSPoint
        if let button, let window = button.window,
           case let iconFrame = window.convertToScreen(button.convert(button.bounds, to: nil)),
           NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: iconFrame.midX, y: iconFrame.midY)) }) {
            anchor = NSPoint(x: iconFrame.midX, y: iconFrame.minY - 6)
        } else {
            // Kein Symbol oder Symbol hinter der Notch/außerhalb jedes Bildschirms (gemessen 14.11.).
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            anchor = NSPoint(x: visible.midX, y: visible.maxY - 8)
        }
        return present(ids: ids, anchor: anchor, floating: true)
    }

    private func present(ids: [UUID], anchor: NSPoint, floating: Bool) -> Bool {
        let store = NotesStore.shared
        guard !NotesPreferences.quickNotes(ids: ids, in: store.notes).isEmpty else { return false }

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
            },
            onOpacityChange: { [weak self] value in self?.panel?.alphaValue = value }
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
        panel.alphaValue = NotesSettings.quickNotesOpacity
        panel.isMovableByWindowBackground = floating

        self.anchor = anchor
        isFloating = floating
        userMoved = false
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
        if floating {
            // Schwebend: Klicks daneben (Video, andere App) schließen nicht – nur Esc oder das Kürzel.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.noteMove() }
            })
            // Messpunkt: verschwindet das Fenster ohne `close()`?
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { _ in quickNotesLog.notice("floating panel resigned key") })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
            ) { note in
                let visible = (note.object as? NSWindow)?.occlusionState.contains(.visible) ?? false
                quickNotesLog.notice("floating panel occlusion: visible=\(visible, privacy: .public)")
            })
        } else {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.close() }
            })
            // Clicks into other apps — same mechanism as TranslateQuickPanel.
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
        }

        panel.makeKeyAndOrderFront(nil)
        quickNotesLog.notice("present: floating=\(floating, privacy: .public) tabs=\(ids.count, privacy: .public) visible=\(panel.isVisible, privacy: .public)")
        return true
    }

    /// Editor der Notiz `noteID`, wenn das Panel sie gerade als Reiter zeigt (Sprachnotiz, Michael 14.11.:
    /// „Fenster soll offen bleiben, bis ich Esc drücke“) – dann geht das Diktat direkt in diesen Editor.
    func liveTextView(for noteID: UUID) -> NSTextView? {
        guard let panel, panel.isVisible, Self.lastSelectedID == noteID, let root = panel.contentView else { return nil }
        return Self.firstTextView(in: root)
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? PlainTextEditor.PasteAwareTextView { return textView }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

    /// Ein vom Nutzer verschobenes schwebendes Panel bleibt, wo es ist (auch beim Vergrößern).
    private func noteMove() {
        guard let panel, let anchor else { return }
        let expected = Self.placedOrigin(size: panel.frame.size, anchor: anchor, screens: NSScreen.screens)
        if panel.frame.origin != expected { userMoved = true }
    }

    /// Oben mittig unter dem Anker, waagrecht **und senkrecht** ganz im sichtbaren Bereich. Gemessen 14.11.
    /// (MacBook, Symbol hinter der Notch): Anker außerhalb jedes Bildschirms → Panel lag mit y = 973 unter der
    /// Unterkante eines 956 px hohen Bildschirms, offen, aber unsichtbar.
    static func placedOrigin(size: CGSize, anchor: NSPoint, screens: [NSScreen]) -> NSPoint {
        let screen = screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main ?? screens.first
        return clampedOrigin(size: size, anchor: anchor, visible: screen?.visibleFrame)
    }

    /// Reine Rechnung (getestet): Mitte unter `anchor`, 8 pt Abstand zu den Kanten des sichtbaren Bereichs.
    nonisolated static func clampedOrigin(size: CGSize, anchor: NSPoint, visible: CGRect?) -> NSPoint {
        var x = anchor.x - size.width / 2
        var y = anchor.y - size.height
        if let visible {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    /// Centred under the icon, top edge fixed, kept on the icon's screen.
    private func place(_ panel: NSPanel) {
        guard let anchor, !userMoved else { return }
        let origin = Self.placedOrigin(size: panel.frame.size, anchor: anchor, screens: NSScreen.screens)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    func close(_ reason: String = #function, caller: String = #fileID, line: Int = #line) {
        guard let panel else { return }
        quickNotesLog.notice("close: reason=\(reason, privacy: .public) from \(caller, privacy: .public):\(line, privacy: .public) floating=\(self.isFloating, privacy: .public)")
        lastClose = Date()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        self.panel = nil
        anchor = nil
        isFloating = false
        userMoved = false
        panel.orderOut(nil)
        // Tears the SwiftUI tree down so the editor's onDisappear saves the last
        // keystrokes now.
        panel.contentViewController = nil
    }
}
