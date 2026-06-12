import AppKit
import SwiftUI

/// Titled non-activating panel for the preview window. Same idea as the picker
/// popup's `NonActivatingKeyPanel`: the preview is a regular-looking window
/// (titlebar, close, resize), but it must NOT activate Tippi when it appears —
/// otherwise the source app loses focus, its selection collapses, and the
/// "Einfügen" button has nothing left to replace by the time the user clicks it.
private final class NonActivatingTitledPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

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
        let window = NonActivatingTitledPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Tippi"
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.worksWhenModal = true
        window.center()

        // Wire up the delegate so native close (red X, Cmd-W) resets state too
        closeDelegate.onClose = { [weak self] in
            guard let self, self.window != nil else { return }
            self.window = nil
            self.onCancelCallback?()
            self.onCancelCallback = nil
        }
        window.delegate = closeDelegate

        self.window = window

        // CRITICAL: do NOT call NSApp.activate here. Activating Tippi would
        // steal focus from the source app, collapsing its selection — by the
        // time the user clicks "Einfügen", there is nothing left to replace
        // and the result silently falls back to clipboard-only. The
        // non-activating panel + canBecomeKey override lets the preview
        // receive clicks and keyboard shortcuts (Cmd+Return etc.) without
        // taking activation away from the source app.
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
