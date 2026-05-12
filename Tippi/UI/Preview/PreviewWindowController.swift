import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    private var window: NSWindow?

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

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
