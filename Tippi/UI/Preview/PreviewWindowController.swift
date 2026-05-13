import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    private var window: NSWindow?
    private var onCancelCallback: (() -> Void)?

    // NSWindowDelegate that fires when the window closes by ANY means (red X, Cmd-W, etc.)
    private final class CloseDelegate: NSObject, NSWindowDelegate {
        var onClose: (() -> Void)?
        func windowWillClose(_ notification: Notification) {
            onClose?()
        }
    }
    private let closeDelegate = CloseDelegate()

    var isOpen: Bool { window != nil }

    func show(
        prompt: DemoPrompt,
        originalText: String,
        sourceApp: NSRunningApplication?,
        onReplace: @escaping (String) -> Void,
        onAppend: @escaping (String) -> Void,
        onCopy: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        close()

        // Capture cancel callback so the delegate can call it on native close
        onCancelCallback = onCancel

        let view = PreviewView(
            prompt: prompt,
            originalText: originalText,
            sourceAppName: sourceApp?.localizedName,
            onReplace: { [weak self] text in
                self?.close()
                onReplace(text)
            },
            onAppend: { [weak self] text in
                self?.close()
                onAppend(text)
            },
            onCopy: { [weak self] text in
                self?.close()
                onCopy(text)
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tippi"
        window.styleMask = [.titled, .closable, .resizable]
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.setContentSize(NSSize(width: 640, height: 480))

        // Wire up the delegate so native close (red X, Cmd-W) resets state too
        closeDelegate.onClose = { [weak self] in
            guard let self, self.window != nil else { return }
            self.window = nil
            self.onCancelCallback?()
            self.onCancelCallback = nil
        }
        window.delegate = closeDelegate

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        // Nil out window BEFORE calling orderOut so the delegate guard fires correctly
        let w = window
        window = nil
        onCancelCallback = nil
        w?.orderOut(nil)
    }
}
