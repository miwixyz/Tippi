import AppKit
import SwiftUI

@MainActor
final class PromptPopupController {
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    var isOpen: Bool { panel != nil }

    func show(
        at point: NSPoint,
        prompts: [DemoPrompt],
        onSelect: @escaping (DemoPrompt) -> Void,
        onDismiss: @escaping () -> Void,
        audioRecorder: AudioRecorder? = nil,
        onVoiceTranscribed: @escaping (String) -> Void = { _ in }
    ) {
        guard panel == nil else { return }

        var view = PromptPopupView(
            prompts: prompts,
            onSelect: { [weak self] prompt in
                self?.close()
                onSelect(prompt)
            },
            onDismiss: { [weak self] in
                self?.close()
                onDismiss()
            }
        )
        view.audioRecorder       = audioRecorder
        view.onVoiceTranscribed  = { [weak self] text in
            self?.close()
            onVoiceTranscribed(text)
        }

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = NSPanel(
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

        NSApp.activate(ignoringOtherApps: true)
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
