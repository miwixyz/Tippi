import AppKit
import SwiftUI

// `NonKeyPanel` and `ClickableHostingView` live in `NonKeyPanelChrome.swift`,
// shared with `EmojiSuggestionPanel`. They used to be duplicated here, which
// is how the 2026-09-14 glass fix reached only one of the two panels.

@MainActor
final class SelectionActionBarPanel {
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var autoHideTimer: Timer?
    private var idleSeconds: TimeInterval = 0
    private var appActivationObserver: NSObjectProtocol?
    /// Where the bar belongs — the selection (or the mouse-position fallback).
    /// Moving the pointer well away from this plus the bar closes it.
    private var selectionZone: CGRect = .null

    /// Identifies one selection: same app, same text, same position.
    private struct SelectionSignature: Equatable {
        let pid: pid_t?
        let text: String
        let location: Int?

        init(_ snapshot: SelectionSnapshot) {
            pid = snapshot.sourceApp?.processIdentifier
            text = snapshot.text
            location = snapshot.range.map { $0.location } ?? snapshot.nativeRange.map { $0.location }
        }
    }
    /// The selection the bar is showing for right now.
    private var shownSignature: SelectionSignature?
    /// The last selection whose bar was closed without an action being taken
    /// (pointer moved away, click elsewhere, Escape, app switch, time-out).
    /// The monitor re-checks on every mouse-up anywhere, and many clicks —
    /// menu bar, Dock, a toolbar — leave the selection intact, so this same
    /// selection would otherwise pop the bar straight back up (reported
    /// 2026-09-24: "wenn ich woanders klicke popt das Pop-Up kurz auf").
    private var dismissedSignature: SelectionSignature?

    /// The bar disappears on its own after this much time without the pointer
    /// on it. Before this existed it sat there until the user clicked
    /// somewhere or pressed Escape — so selecting text and then just reading
    /// it left a floating bar covering the next line.
    private static let autoHideAfter: TimeInterval = 5
    private static let autoHideTick: TimeInterval = 0.5

    var isOpen: Bool { panel != nil }

    /// Shows the bar next to `snapshot`'s selection. `onAction` fires with
    /// the chosen local action and the (possibly stale, by the time of a
    /// click) snapshot — the caller re-validates before writing anything
    /// back. `onTranslate` fires with just the captured text — translating
    /// opens a separate window rather than replacing anything in place, so
    /// it doesn't need the element/range the local actions need.
    func show(
        snapshot: SelectionSnapshot,
        onAction: @escaping (LocalTextAction, SelectionSnapshot) -> Void,
        onTranslate: @escaping (String) -> Void
    ) {
        close() // replace whatever's showing, if anything — a new selection wins

        let view = SelectionActionBarView(
            onAction: { [weak self] action in
                onAction(action, snapshot)
                self?.close(afterAction: true)
            },
            onTranslate: { [weak self] in
                onTranslate(snapshot.text)
                self?.close(afterAction: true)
            }
        )

        let popupSize = CGSize(width: SelectionActionBarView.width, height: SelectionActionBarView.height)
        let panel = NonKeyPanel(
            contentRect: NSRect(origin: .zero, size: popupSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = ClickableHostingView(rootView: view)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Belt and suspenders alongside `canBecomeKey == false`: never let
        // ordering this front pull key status onto it either.
        panel.becomesKeyOnlyIfNeeded = true

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Two cases fall back to the mouse position instead of the AX
        // bounds: (1) no bounds at all — some apps don't implement the AX
        // bounds-for-range attribute; (2) bounds that are implausibly tall
        // for a text selection. Observed in real-world testing: some apps
        // report the bounds of the whole text container instead of just the
        // selected range, which put the bar directly on top of the
        // selected line instead of clearly above/below it — a suspiciously
        // large height is the signal that happened, not a genuine
        // multi-line selection.
        // (3) Degenerate bounds. Electron-based apps answer the bounds query
        // with an all-zero rect instead of failing it — measured 2026-09-14,
        // `bounds=(0.0, 0.0, 0.0, 0.0)`. Zero height passed the "not too tall"
        // test below, so the bar was anchored at the screen origin, which on
        // macOS is the *bottom left* corner: the popup appeared in a different
        // corner of the display from the text it belonged to.
        let maxPlausibleSelectionHeight: CGFloat = 80
        let isUsable: (CGRect) -> Bool = { rect in
            rect.width > 0
                && rect.height > 0
                && rect.height <= maxPlausibleSelectionHeight
                // A selection has to sit on a screen the user can see. An
                // off-screen rect is another way apps signal "no idea".
                && NSScreen.screens.contains { $0.frame.intersects(rect) }
        }
        let anchorBounds: CGRect
        let hasRealBounds: Bool
        if let bounds = snapshot.bounds, isUsable(bounds) {
            anchorBounds = bounds
            hasRealBounds = true
        } else {
            anchorBounds = CGRect(origin: NSEvent.mouseLocation, size: .zero)
            hasRealBounds = false
        }

        // A dismissed selection only comes back when the mouse went up ON it —
        // that is someone selecting it again on purpose. A click anywhere else
        // that merely left it selected must not resurrect the bar. Without real
        // bounds there is no way to tell the two apart, so those apps keep the
        // old behaviour.
        let signature = SelectionSignature(snapshot)
        if hasRealBounds, signature == dismissedSignature,
           !SelectionPopupPositioner.pointerIsOnSelection(NSEvent.mouseLocation, selectionBounds: anchorBounds) {
            return
        }
        dismissedSignature = nil
        shownSignature = signature
        let origin = SelectionPopupPositioner.origin(
            for: anchorBounds,
            popupSize: popupSize,
            position: SelectionPopupSettings.position,
            screenFrame: screenFrame
        )
        panel.setFrameOrigin(origin)

        self.panel = panel
        selectionZone = anchorBounds

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        // The panel is never key, so SwiftUI's `.onExitCommand` (which only
        // fires for a key window) can't be used for Escape-to-dismiss —
        // watch for it directly instead. Global, not local: Escape is
        // pressed in the app the user is actually working in, not in Tippi.
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // kVK_Escape
            Task { @MainActor in self?.close() }
        }

        // Switching to another app (⌘-Tab, Dock, Mission Control) involves no
        // click, so the mouse monitor above never sees it — the bar used to
        // float over the next app until the auto-hide ran out. Tippi's own
        // activation counts too: the bar belongs to the source app's text.
        let sourcePID = snapshot.sourceApp?.processIdentifier
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.processIdentifier != sourcePID else { return }
            Task { @MainActor in self?.close() }
        }

        // `orderFront`, not `makeKeyAndOrderFront` — the whole point of this
        // panel is that it never becomes key (see `NonKeyPanel`'s doc
        // comment). The source app stays frontmost and keeps the keyboard.
        panel.orderFront(nil)
        startAutoHide()
    }

    // MARK: - Auto-hide

    /// Polls the pointer instead of using an `NSTrackingArea`. The bar is a
    /// non-key panel whose hosting view deliberately dodges the normal
    /// responder chain (see `ClickableHostingView`), and tracking areas on it
    /// miss enter/exit often enough to hide the bar out from under a pointer
    /// that is heading for a button. Half-second polling costs nothing and
    /// cannot get the state wrong.
    private func startAutoHide() {
        stopAutoHide()
        idleSeconds = 0
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoHideTick, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tickAutoHide() }
        }
    }

    private func tickAutoHide() {
        guard let panel else { return stopAutoHide() }
        // Pointer on the bar means the user is reaching for it — that is the
        // one moment it must not vanish. Reset rather than pause, so moving
        // away restarts the full countdown instead of the remainder.
        let pointer = NSEvent.mouseLocation
        if NSMouseInRect(pointer, panel.frame, false) {
            idleSeconds = 0
            return
        }
        // Pointer moved on to something else entirely — no reason to wait
        // out the countdown (2026-09-24: bar stayed over an open Apple menu).
        if SelectionPopupPositioner.pointerHasLeft(pointer, popupFrame: panel.frame, selectionBounds: selectionZone) {
            return close()
        }
        idleSeconds += Self.autoHideTick
        if idleSeconds >= Self.autoHideAfter { close() }
    }

    private func stopAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    /// `afterAction`: the user used the bar, so there is nothing to remember —
    /// every other close counts as "not wanted for this selection".
    func close(afterAction: Bool = false) {
        if !afterAction, let shown = shownSignature {
            dismissedSignature = shown
        }
        shownSignature = nil
        stopAutoHide()
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        selectionZone = .null
        panel?.orderOut(nil)
        panel = nil
    }
}
