import AppKit
import SwiftUI

/// Borderless, non-activating floating panel for the selection action bar.
/// Same `NonActivatingKeyPanel` pattern as `TranslateQuickPanel`/
/// `PromptPopupController` (proven in this codebase — `acceptsFirstResponder`
/// override included, since without it borderless panels can silently fail
/// to route mouse events even with `canBecomeKey` alone).
private final class NonActivatingKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class SelectionActionBarPanel {
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

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
                self?.close()
            },
            onTranslate: { [weak self] in
                onTranslate(snapshot.text)
                self?.close()
            }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let popupSize = CGSize(width: SelectionActionBarView.width, height: SelectionActionBarView.height)
        let panel = NonActivatingKeyPanel(
            contentRect: NSRect(origin: .zero, size: popupSize),
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
        let maxPlausibleSelectionHeight: CGFloat = 80
        let anchorBounds: CGRect
        if let bounds = snapshot.bounds, bounds.height <= maxPlausibleSelectionHeight {
            anchorBounds = bounds
        } else {
            anchorBounds = CGRect(origin: NSEvent.mouseLocation, size: .zero)
        }
        let origin = SelectionPopupPositioner.origin(
            for: anchorBounds,
            popupSize: popupSize,
            position: SelectionPopupSettings.position,
            screenFrame: screenFrame
        )
        panel.setFrameOrigin(origin)

        self.panel = panel

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

        // Do NOT call NSApp.activate — matches TranslateQuickPanel/
        // PromptPopupController exactly, for the same reason: the source
        // app must stay frontmost, only this panel becomes key within
        // Tippi's own process so its buttons receive clicks.
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
}
