import AppKit
import SwiftUI

/// Borderless non-activating panel that can become key without activating Tippi.
/// The defaults `NSPanel` provides aren't enough for borderless windows — we need
/// to explicitly opt-in to key-window status so SwiftUI's `.onKeyPress` modifiers
/// receive events while the source app remains active (preserving its selection).
private final class NonActivatingKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class PromptPopupController {
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?
    private weak var audioRecorder: AudioRecorder?

    var isOpen: Bool { panel != nil }

    func show(
        at point: NSPoint,
        prompts: [DemoPrompt],
        localActions: [LocalTextAction] = [],
        localActionsReady: Bool = true,
        onSelect: @escaping (DemoPrompt) -> Void,
        onLocalAction: @escaping (LocalTextAction) async -> String? = { _ in nil },
        onDismiss: @escaping () -> Void,
        audioRecorder: AudioRecorder? = nil,
        voiceMode: VoiceMode = .dictate,
        onVoiceTranscribed: @escaping (String) -> Void = { _ in },
        onDirectInsert: (() -> Void)? = nil
    ) {
        guard panel == nil else { return }
        self.audioRecorder = audioRecorder

        let view = PromptPopupView(
            prompts: prompts,
            localActions: localActions,
            localActionsReady: localActionsReady,
            onSelect: { [weak self] prompt in
                self?.close()
                onSelect(prompt)
            },
            onLocalAction: onLocalAction,
            onDismiss: { [weak self] in
                self?.close()
                onDismiss()
            },
            onDirectInsert: onDirectInsert.map { insert in
                { [weak self] in
                    self?.close()
                    insert()
                }
            },
            audioRecorder: audioRecorder,
            onVoiceTranscribed: { [weak self] text in
                self?.close()
                onVoiceTranscribed(text)
            },
            voiceMode: voiceMode
        )

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = NonActivatingKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 340),
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

        // Layout first so fittingSize reflects actual content height
        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.view.fittingSize
        let panelSize = NSSize(
            width: max(fittingSize.width, 290),
            height: max(fittingSize.height, 100)
        )
        panel.setContentSize(panelSize)
        positionPanel(panel, near: point)

        self.panel = panel

        // Close on click outside Tippi
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
                onDismiss()
            }
        }

        // Close on losing key (e.g., user switches app via ⌘-Tab)
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
                onDismiss()
            }
        }

        // CRITICAL: do NOT call NSApp.activate here.
        //
        // Activating Tippi would steal focus from the source app, which collapses
        // the user's selection in non-AppKit apps (Electron/Chromium, web views,
        // Catalyst) — making AX-based replacement impossible afterwards.
        //
        // The non-activating panel + `canBecomeKey = true` override is what lets
        // the popup receive keystrokes while the source app remains active with
        // its selection intact.
        panel.makeKeyAndOrderFront(nil)
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
        panel?.orderOut(nil)
        panel = nil
        if audioRecorder?.isRecording == true {
            _ = audioRecorder?.stop()
        }
        audioRecorder = nil
    }

    private func positionPanel(_ panel: NSPanel, near point: NSPoint) {
        let popupSize = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame

        var x = point.x
        var y = point.y - popupSize.height - 12 // below cursor, with gap

        if x + popupSize.width > visibleFrame.maxX - 8 {
            x = visibleFrame.maxX - popupSize.width - 8
        }
        if x < visibleFrame.minX + 8 {
            x = visibleFrame.minX + 8
        }
        if y < visibleFrame.minY + 8 {
            y = point.y + 12 // flip above cursor
        }
        if y + popupSize.height > visibleFrame.maxY - 8 {
            y = visibleFrame.maxY - popupSize.height - 8
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
