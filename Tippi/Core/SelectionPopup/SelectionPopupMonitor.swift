import AppKit
import ApplicationServices
import os

private let selectionPopupLog = Logger(subsystem: "com.tippi.app", category: "selection-popup")

/// Everything the action bar needs to show itself and later replace the
/// selected text — captured once at mouse-up time while the selection is
/// still live, matching the same "capture the AX element+range early" habit
/// `AppDelegate.handleTriggered` already uses for the hotkey flow.
///
/// `element`/`range`/`sourceApp` are for a selection in some OTHER app,
/// read/written via Accessibility. `nativeTextView`/`nativeRange` are for a
/// selection inside Tippi's OWN Notes editor — direct AppKit access instead
/// of chasing our own process through the Accessibility server, which proved
/// unreliable for self-inspection (real bug, 2026-09-13: a local action's
/// result got appended after the original text instead of replacing it).
/// Exactly one pair is populated, never both.
struct SelectionSnapshot {
    let text: String
    let element: AXUIElement?
    let range: CFRange?
    /// nil when the source app doesn't implement the bounds-for-range AX
    /// attribute — the panel falls back to the mouse position instead of
    /// refusing to show at all.
    let bounds: CGRect?
    let sourceApp: NSRunningApplication?
    let nativeTextView: NSTextView?
    let nativeRange: NSRange?
}

/// Watches for text selections system-wide via a mouse-up monitor, the same
/// `NSEvent.addGlobalMonitorForEvents` approach as `GlobalKeyMonitor` and
/// `SnippetKeystrokeMonitor` (Accessibility permission only). Fires
/// `onSelection` when a selection worth showing the bar for appears, and
/// `onNoSelection` on every other mouse-up (a plain click, or a selection
/// that dropped below the minimum length) — the caller treats that as "hide
/// the bar if it's showing."
@MainActor
final class SelectionPopupMonitor: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var debounceTask: Task<Void, Never>?

    private let onSelection: (SelectionSnapshot) -> Void
    private let onNoSelection: () -> Void

    /// Selections shorter than this don't trigger the bar. `captureFocusedSelectionRange`
    /// already filters out a bare cursor position (range.length == 0); this
    /// additionally filters a stray 1-character selection, which is far
    /// more often an accidental drag than something worth acting on.
    private static let minimumSelectionLength = 2

    init(onSelection: @escaping (SelectionSnapshot) -> Void, onNoSelection: @escaping () -> Void) {
        self.onSelection = onSelection
        self.onNoSelection = onNoSelection
    }

    func start() {
        guard !isActive else { return }
        lastError = nil
        guard AXIsProcessTrusted() else {
            lastError = "Grant Accessibility permission so the selection bar can find your selection."
            selectionPopupLog.notice("SelectionPopupMonitor — not trusted (Accessibility permission missing)")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.scheduleCheck()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.scheduleCheck()
            return event
        }

        guard globalMonitor != nil else {
            lastError = "Couldn't register selection monitor."
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            return
        }

        isActive = true
        selectionPopupLog.notice("SelectionPopupMonitor active")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        debounceTask?.cancel()
        isActive = false
    }

    private func scheduleCheck() {
        // Never trigger while interacting with Tippi's own UI (Settings, the
        // snippet editor, this bar itself) — same guard the snippet
        // keystroke engine uses for the same reason.
        guard !NSApp.isActive else {
            selectionPopupLog.notice("scheduleCheck: skipped, Tippi itself is active")
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            // Right at mouseUp, some apps haven't committed the selection to
            // their AX tree yet — same class of timing issue `TextInsertion`
            // already works around with its own settle delays around paste.
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            self?.checkSelection()
        }
    }

    private func checkSelection() {
        // Tippi's own Notes editor bypasses the "never trigger while Tippi
        // itself is active" guard below — that guard exists to stop this bar
        // popping up over Settings or other Tippi chrome, but Notes is a
        // real content-editing surface where the same feature is exactly as
        // wanted as in any other app. Uses direct AppKit, not Accessibility,
        // for both the same self-inspection reasons documented on
        // `SelectionSnapshot`.
        if NSApp.isActive, let textView = AppDelegate.focusedNotesTextView() {
            checkNativeSelection(in: textView)
            return
        }

        // Never trigger while interacting with any OTHER Tippi UI (Settings,
        // the snippet editor, this bar itself) — same guard the snippet
        // keystroke engine uses for the same reason.
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            selectionPopupLog.notice("checkSelection: no eligible frontmost app")
            onNoSelection()
            return
        }
        guard let (element, range) = TextCapture.captureFocusedSelectionRange(in: app) else {
            selectionPopupLog.notice("checkSelection: no selection range in app=\(app.localizedName ?? "?", privacy: .public)")
            onNoSelection()
            return
        }
        guard range.length >= Self.minimumSelectionLength else {
            selectionPopupLog.notice("checkSelection: range too short (\(range.length, privacy: .public) chars) in app=\(app.localizedName ?? "?", privacy: .public)")
            onNoSelection()
            return
        }
        guard let text = TextCapture.selectedText(from: element),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            selectionPopupLog.notice("checkSelection: range found but no text readable, app=\(app.localizedName ?? "?", privacy: .public)")
            onNoSelection()
            return
        }
        let bounds = TextCapture.boundsForSelection(element: element, range: range)
        selectionPopupLog.notice("checkSelection: match, \(text.count, privacy: .public) chars, bounds=\(bounds.map { "\($0)" } ?? "nil", privacy: .public), app=\(app.localizedName ?? "?", privacy: .public)")
        onSelection(SelectionSnapshot(
            text: text, element: element, range: range, bounds: bounds, sourceApp: app,
            nativeTextView: nil, nativeRange: nil
        ))
    }

    private func checkNativeSelection(in textView: NSTextView) {
        let range = textView.selectedRange()
        guard range.length >= Self.minimumSelectionLength else {
            selectionPopupLog.notice("checkNativeSelection: range too short (\(range.length, privacy: .public) chars)")
            onNoSelection()
            return
        }
        let text = (textView.string as NSString).substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onNoSelection()
            return
        }
        let bounds = textView.firstRect(forCharacterRange: range, actualRange: nil)
        selectionPopupLog.notice("checkNativeSelection: match, \(text.count, privacy: .public) chars in Notes editor")
        onSelection(SelectionSnapshot(
            text: text, element: nil, range: nil,
            bounds: bounds.isNull || bounds == .zero ? nil : bounds,
            sourceApp: nil, nativeTextView: textView, nativeRange: range
        ))
    }
}
