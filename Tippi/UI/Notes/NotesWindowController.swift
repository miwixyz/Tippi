import AppKit
import SwiftUI

/// Standalone, resizable Notes window.
///
/// Unlike `PreviewWindowController`'s non-activating panel (which must not
/// steal focus from another app, so a live text selection there survives
/// until "Einfügen" is clicked), Notes is a self-contained editing surface
/// the user opens deliberately from the menu bar or a hotkey — it activates
/// normally, the same as the Settings/Welcome windows, just resizable and
/// with its frame synced via `NotesPreferences` instead of AppKit's local-only
/// `setFrameAutosaveName`.
@MainActor
final class NotesWindowController {
    private var windowController: NSWindowController?
    private let minSize = NSSize(width: 480, height: 320)
    private let defaultSize = NSSize(width: 680, height: 440)

    var isOpen: Bool { windowController?.window?.isVisible ?? false }

    /// Brings the Notes window to front, creating it on first call. Always
    /// "show", never "toggle" — a hotkey press while the user is mid-typing
    /// closing the window on them would feel like data loss, even though
    /// content autosaves (see `NotesEditorView`).
    func show() {
        NSApp.activate()

        if windowController == nil {
            windowController = makeWindowController()
        }
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let hosting = NSHostingController(rootView: NotesRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "notes.window.title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.delegate = FrameSaveDelegate.shared

        if let savedFrame = NotesPreferences.windowFrame {
            window.setFrame(savedFrame, display: false)
        } else {
            window.setContentSize(defaultSize)
            window.center()
        }

        return NSWindowController(window: window)
    }

    /// Persists the frame to `NotesPreferences` (iCloud key-value store) on
    /// move/resize/close — coalesced to those events rather than every
    /// intermediate drag frame during a live resize.
    @MainActor
    private final class FrameSaveDelegate: NSObject, NSWindowDelegate {
        static let shared = FrameSaveDelegate()
        func windowDidEndLiveResize(_ notification: Notification) { persist(notification) }
        func windowDidMove(_ notification: Notification) { persist(notification) }
        func windowWillClose(_ notification: Notification) { persist(notification) }

        private func persist(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            NotesPreferences.windowFrame = window.frame
        }
    }
}
