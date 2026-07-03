import AppKit
import SwiftUI

/// Borderless, non-activating floating panel for the Translate Quick Panel —
/// a Spotlight-style "type text, get translation" window. Mirrors
/// `PromptPopupController`'s `NonActivatingKeyPanel` exactly (proven pattern
/// in this codebase) — `acceptsFirstResponder` override included, since
/// without it borderless panels can silently fail to route keyboard/mouse
/// events even with `canBecomeKey` alone.
private final class NonActivatingKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class TranslateQuickPanel {
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private weak var audioRecorder: AudioRecorder?

    var isOpen: Bool { panel != nil }

    /// Opens the panel, or closes it if already open (toggle — same feel as
    /// Spotlight when you press its hotkey a second time). `audioRecorder`
    /// (the app-wide shared instance) powers the in-panel mic button; pass
    /// nil to disable voice input.
    func toggle(audioRecorder: AudioRecorder?) {
        if isOpen {
            close()
        } else {
            show(audioRecorder: audioRecorder)
        }
    }

    private func show(audioRecorder: AudioRecorder?) {
        guard panel == nil else { return }
        self.audioRecorder = audioRecorder

        let view = TranslateQuickView(
            onClose: { [weak self] in self?.close() },
            audioRecorder: audioRecorder
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = NonActivatingKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
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

        // Center horizontally, positioned in the upper third — same spot
        // Spotlight opens at, so it feels familiar instead of appearing
        // wherever the mouse happens to be.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - panel.frame.width / 2
            let y = frame.maxY - frame.height * 0.32 - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        self.panel = panel

        // Close on click outside — same mechanism as PromptPopupController,
        // NOT an NSWindowDelegate callback (windowDidResignKey fired
        // spuriously right after open in testing, self-closing the panel
        // before the user could interact with it at all).
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        // Match the system light/dark appearance at open, and keep it in sync
        // live if the user toggles the system theme while the panel is open.
        // A borderless non-activating panel can snapshot `.aqua` at creation
        // and then not follow the system, so we drive it explicitly.
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

        // Do NOT call NSApp.activate — see PromptPopupController for why.
        // canBecomeKey + acceptsFirstResponder is what lets this receive
        // keystrokes and clicks without activating the app.
        panel.makeKeyAndOrderFront(nil)
    }

    /// Sets the panel's appearance to the current system light/dark mode.
    private func applySystemAppearance(to panel: NSPanel) {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    func close() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            appearanceObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        // Stop any in-flight recording so the shared recorder is free for
        // dictation and doesn't keep the mic hot after the panel closes.
        if audioRecorder?.isRecording == true { _ = audioRecorder?.stop() }
        audioRecorder = nil
        TranslateSpeech.shared.stop()
    }
}
