import AppKit
import SwiftUI

/// Non-activating, **non-key** floating panel for the selection action bar.
///
/// Deliberately NOT the `NonActivatingKeyPanel` pattern `TranslateQuickPanel`/
/// `PromptPopupController` use — those panels have a text field the user
/// types into, so THEY genuinely need key-window status to receive
/// keystrokes. This bar is pure mouse-click buttons with no text input at
/// all, and becoming key was a real showstopper bug (found 2026-09-09):
/// on macOS there is exactly one key window system-wide, so once this panel
/// became key, ⌘C/⌘V/⌘X/Delete/typing and even Escape all stopped reaching
/// the app the user was actually working in — every one of those keystrokes
/// was silently swallowed by a panel that has no text field to do anything
/// with them.
///
/// `canBecomeKey` is explicitly `false` here. Buttons still respond to the
/// very first click without that: `ClickableHostingView.acceptsFirstMouse`
/// tells AppKit this view accepts clicks even while its window isn't key,
/// which is the standard, narrower mechanism background utility panels use
/// instead of grabbing key status wholesale.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// `NSHostingView` doesn't accept clicks in a non-key window by default —
/// this override is the whole reason the panel can stay non-key and still
/// be clickable.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SelectionActionBarPanel {
    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var escapeKeyMonitor: Any?

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
        // The panel is never key, so SwiftUI's `.onExitCommand` (which only
        // fires for a key window) can't be used for Escape-to-dismiss —
        // watch for it directly instead. Global, not local: Escape is
        // pressed in the app the user is actually working in, not in Tippi.
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // kVK_Escape
            Task { @MainActor in self?.close() }
        }

        // `orderFront`, not `makeKeyAndOrderFront` — the whole point of this
        // panel is that it never becomes key (see `NonKeyPanel`'s doc
        // comment). The source app stays frontmost and keeps the keyboard.
        panel.orderFront(nil)
    }

    func close() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}
