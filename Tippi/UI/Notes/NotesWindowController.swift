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
    /// Declares this window a text surface where snippet expansion is wanted.
    /// `SnippetKeystrokeMonitor` allow-lists Tippi's own windows by identifier
    /// — see `expansionAllowedWindowIdentifiers` there. Keep the two in sync;
    /// the raw value is the contract between them.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("TippiNotesWindow")

    private var windowController: NSWindowController?
    private let minSize = NSSize(width: 480, height: 320)
    private let defaultSize = NSSize(width: 680, height: 440)

    var isOpen: Bool { windowController?.window?.isVisible ?? false }

    /// Brings the Notes window to front, creating it on first call. Always
    /// "show", never "toggle" — a hotkey press while the user is mid-typing
    /// closing the window on them would feel like data loss, even though
    /// content autosaves (see `NotesEditorView`).
    ///
    /// Real question, 2026-09-13: "the Notes window doesn't show up when I
    /// ⌘Tab through open apps — does that need a Dock icon?" Yes — an
    /// LSUIElement app (Tippi's normal menu-bar-only mode) is categorically
    /// excluded from ⌘Tab regardless of window level or collection behavior;
    /// there is no API to opt a single window into the switcher without it.
    /// `.setActivationPolicy(.regular)` while Notes is open gives it both a
    /// Dock icon and a ⌘Tab entry; `FrameSaveDelegate.windowWillClose` flips
    /// back to `.accessory` (the LSUIElement-equivalent Tippi normally runs
    /// as) once Notes closes, so the rest of the app is unaffected.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        if windowController == nil {
            windowController = makeWindowController()
        }
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let hosting = NSHostingController(rootView: NotesRootView(onTogglePin: { [weak self] in
            self?.togglePin()
        }))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "notes.window.title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        // Transparent titlebar merges into the window body; the toolbar's own
        // opaque strip is hidden in NotesRootView, otherwise the edge just moves
        // down a few points instead of disappearing (2026-09-13: "Titelleiste
        // sieht noch nicht schön aus").
        window.titlebarAppearsTransparent = true
        // The window keeps its DEFAULT (solid) background on purpose.
        //
        // It used to be `.clear` with a translucent material over the whole
        // content. That material blurs the wallpaper down to its average colour,
        // so a purple desktop turned the entire window into pink fog — glassEffect
        // and .regularMaterial produced an identical wash (measured 2026-09-14).
        // Finder, Mail and Notes.app do the opposite: solid window body,
        // translucent sidebar only. NotesListView keeps its
        // .scrollContentBackground(.hidden) for exactly that sidebar effect.
        window.identifier = Self.windowIdentifier
        window.delegate = FrameSaveDelegate.shared
        applyPinnedState(to: window)

        if let savedFrame = NotesPreferences.windowFrame {
            window.setFrame(savedFrame, display: false)
        } else {
            window.setContentSize(defaultSize)
            window.center()
        }

        return NSWindowController(window: window)
    }

    /// Toggles "pinned": `.floating` window level + `.canJoinAllSpaces` keeps
    /// the Notes window visible above whatever app becomes frontmost —
    /// switching apps (⌘Tab), Spaces, even into a full-screen app — instead
    /// of it getting buried like a normal window does. Persisted via
    /// `NotesPreferences` so it survives a relaunch on this Mac.
    func togglePin() {
        NotesPreferences.isPinned.toggle()
        if let window = windowController?.window {
            applyPinnedState(to: window)
        }
    }

    private func applyPinnedState(to window: NSWindow) {
        let pinned = NotesPreferences.isPinned
        window.level = pinned ? .floating : .normal
        if pinned {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }

    /// Persists the frame to `NotesPreferences` (iCloud key-value store) on
    /// move/resize/close — coalesced to those events rather than every
    /// intermediate drag frame during a live resize.
    @MainActor
    private final class FrameSaveDelegate: NSObject, NSWindowDelegate {
        static let shared = FrameSaveDelegate()
        func windowDidEndLiveResize(_ notification: Notification) { persist(notification) }
        func windowDidMove(_ notification: Notification) { persist(notification) }
        func windowWillClose(_ notification: Notification) {
            persist(notification)
            // Back to menu-bar-only — see the doc comment on `show()`.
            NSApp.setActivationPolicy(.accessory)
        }

        private func persist(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            NotesPreferences.windowFrame = window.frame
        }
    }
}
