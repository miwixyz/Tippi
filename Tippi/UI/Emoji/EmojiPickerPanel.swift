import AppKit
import SwiftUI

/// Floating panel host for the emoji picker.
///
/// `canBecomeKey` is `true` here — the opposite of `SelectionActionBarPanel`,
/// and deliberately so. That panel is buttons only, and making it key broke
/// ⌘C/⌘V/Delete system-wide (the v2.0.1 showstopper). This one owns a real
/// search field, so it *must* receive keystrokes; the same rule that forbids
/// key status there requires it here. `.nonactivatingPanel` keeps Tippi from
/// stealing full app activation, so the app behind stays visually frontmost.
private final class NonActivatingKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class EmojiPickerPanel {
    private var panel: NSPanel?
    private var model: EmojiPickerModel?
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var appearanceObserver: NSObjectProtocol?

    /// The app that was frontmost when the picker opened — the emoji goes
    /// back there, not to whatever happens to be frontmost after closing.
    private var targetApp: NSRunningApplication?

    var isOpen: Bool { panel != nil }

    func toggle() {
        if isOpen { close() } else { show() }
    }

    private func show() {
        guard panel == nil else { return }

        // Load lazily on first open rather than at launch: most sessions never
        // open the picker, and a 326 KB JSON decode is pure waste until then.
        // `load()` is idempotent and decodes off the main thread.
        EmojiDatabase.shared.load()

        targetApp = NSWorkspace.shared.frontmostApplication

        let model = EmojiPickerModel()
        self.model = model

        let view = EmojiPickerView(
            model: model,
            onPick: { [weak self] emoji in self?.insert(emoji) },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = NonActivatingKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        // Same spot as the translate panel and Spotlight — upper third,
        // horizontally centred — so it appears where the eye already looks.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - panel.frame.width / 2
            let y = frame.maxY - frame.height * 0.32 - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        self.panel = panel

        installKeyMonitor(model: model)

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        applySystemAppearance(to: panel)
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let panel else { return }
                self?.applySystemAppearance(to: panel)
            }
        }

        panel.makeKeyAndOrderFront(nil)
    }

    /// Arrow keys and Return are handled here rather than in SwiftUI because a
    /// focused `TextField` swallows them (↑/↓ move the insertion point). This
    /// is a *local* monitor — it only ever sees events already routed to
    /// Tippi, so unlike a CGEvent tap it cannot affect any other app.
    private func installKeyMonitor(model: EmojiPickerModel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isOpen else { return event }

            switch event.keyCode {
            case 53: // Escape
                self.close()
                return nil
            case 36, 76: // Return, Enter
                if let emoji = model.selected {
                    self.insert(emoji)
                    return nil
                }
                return event
            case 123: // ←
                model.moveSelection(columnDelta: -1)
                return nil
            case 124: // →
                model.moveSelection(columnDelta: 1)
                return nil
            case 125: // ↓
                model.moveSelection(rowDelta: 1)
                return nil
            case 126: // ↑
                model.moveSelection(rowDelta: -1)
                return nil
            case 48: // Tab — same as → so it feels like a completion UI
                model.moveSelection(columnDelta: event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            default:
                return event
            }
        }
    }

    private func insert(_ emoji: Emoji) {
        let app = targetApp
        EmojiSettings.rememberUse(of: emoji.character)
        close()
        Task { @MainActor in
            // Close first, then insert: the target app needs focus back before
            // the synthetic ⌘V lands, otherwise the paste goes nowhere.
            await TextInsertion.insertViaClipboard(emoji.character, into: app)
        }
    }

    private func applySystemAppearance(to panel: NSPanel) {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            appearanceObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        model = nil
        targetApp = nil
    }
}
