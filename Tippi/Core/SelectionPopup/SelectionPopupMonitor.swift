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
    /// Where the left button went down (screen coordinates) — to tell a drag
    /// from a plain click at mouse-up.
    private var mouseDownLocation: CGPoint?

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
        var trusted = AXIsProcessTrusted()
        #if DEBUG
        // Prüfstand-Testkopie hat keine Bedienungshilfen-Freigabe; Tippis Notizen brauchen sie nicht.
        if ProcessInfo.processInfo.environment["TIPPI_REPRO_NOTES_SELECTION"] != nil { trusted = true }
        #endif
        guard trusted else {
            lastError = String(localized: "error.accessibility.selection")
            selectionPopupLog.debug("SelectionPopupMonitor — not trusted (Accessibility permission missing)")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            // Clicks on Tippi's own floating panels (this bar, emoji, translate …)
            // are not selections — and treating a click on a bar button as "plain
            // click, hide the bar" would close it before the button fires.
            guard !(event.window is NSPanel) else { return event }
            self?.handle(event)
            if event.type == .leftMouseDown { self?.evaluateAfterTracking(event) }
            return event
        }

        guard globalMonitor != nil else {
            lastError = String(localized: "error.monitor.selection")
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            return
        }

        isActive = true
        selectionPopupLog.debug("SelectionPopupMonitor active")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        debounceTask?.cancel()
        isActive = false
    }

    /// Pure gate, so the rule is testable without a running app or a window.
    ///
    /// The bar is suppressed inside Tippi's own UI — Settings, the snippet
    /// editor, the bar itself — but the Notes editor is an ordinary content
    /// surface and is explicitly let through.
    nonisolated static func shouldConsiderSelection(appIsActive: Bool, notesEditorHasFocus: Bool) -> Bool {
        !appIsActive || notesEditorHasFocus
    }

    /// A selection the user made themselves: a drag, a double/triple click, or a
    /// shift-click. A plain click is not — many apps select a field's whole
    /// content when it is merely clicked (Reminders' time field "09:00"), and the
    /// bar popped up there (Michael, 2026-10-07, screenshot). Pure for testing.
    nonisolated static func isUserSelectionGesture(mouseDown: CGPoint?, mouseUp: CGPoint,
                                                   clickCount: Int, shiftHeld: Bool) -> Bool {
        if clickCount >= 2 || shiftHeld { return true }
        guard let mouseDown else { return false }
        return hypot(mouseUp.x - mouseDown.x, mouseUp.y - mouseDown.y) >= 4
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            mouseDownLocation = NSEvent.mouseLocation
            return
        }
        handleMouseUp(clickCount: event.clickCount, shiftHeld: event.modifierFlags.contains(.shift))
    }

    /// Text views (the Notes editor) track the mouse in their own loop and swallow
    /// the mouse-up — the local monitor never sees it. Measured 2026-10-07 with the
    /// debug repro `TIPPI_REPRO_NOTES_SELECTION`: a double-click in a note delivered
    /// only the two mouse-downs, so since 2.23.1 (which waits for the mouse-up) the
    /// bar no longer appeared in Notes. A block in the default run-loop mode runs only
    /// once that tracking loop has ended; if the button is up by then, the mouse-up
    /// was swallowed and is evaluated here. If it is still down, the real mouse-up
    /// will reach the monitor.
    private func evaluateAfterTracking(_ mouseDown: NSEvent) {
        let clicks = mouseDown.clickCount
        let shift = mouseDown.modifierFlags.contains(.shift)
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            // concurrency-lint: on-main RunLoop.main runs its blocks on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.mouseDownLocation != nil,
                      NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.handleMouseUp(clickCount: clicks, shiftHeld: shift)
            }
        }
    }

    private func handleMouseUp(clickCount: Int, shiftHeld: Bool) {
        let isGesture = Self.isUserSelectionGesture(
            mouseDown: mouseDownLocation, mouseUp: NSEvent.mouseLocation,
            clickCount: clickCount, shiftHeld: shiftHeld)
        mouseDownLocation = nil
        guard isGesture else {
            // A plain click elsewhere: hide the bar, don't look for a selection —
            // otherwise a field that keeps its selection brought it straight back.
            debounceTask?.cancel()
            onNoSelection()
            return
        }
        scheduleCheck()
    }

    private func scheduleCheck() {
        // Never trigger while interacting with Tippi's own UI (Settings, the
        // snippet editor, this bar itself) — EXCEPT the Notes editor, which is
        // an ordinary content surface where the bar is wanted.
        //
        // `checkSelection()` already knows that and bypasses the app-level
        // guard for the focused Notes text view. It never got the chance: this
        // earlier guard returned first, so the exception below it was dead code
        // and selecting text in Notes produced nothing (reported 2026-09-20).
        //
        // Third instance of the same shape in one day — a guard on an earlier
        // layer silently defeating the special case on a later one. The snippet
        // engine had it (fixed in 2.11.4), and so did this. When a feature is
        // excluded "because Tippi is frontmost", check whether the exclusion is
        // really about the app or about one particular window.
        guard Self.shouldConsiderSelection(appIsActive: NSApp.isActive,
                                           notesEditorHasFocus: AppDelegate.focusedNotesTextView() != nil) else {
            selectionPopupLog.debug("scheduleCheck: skipped, Tippi UI other than Notes is active")
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

    // Every log call in this file is `.debug`, never `.notice`. This runs once
    // per left-click while the feature is on, and `os.Logger` persists
    // `.notice` to disk but not `.debug` — at `.notice` it writes a lasting
    // record of which app was clicked and when, which is both write load and a
    // usage profile nobody asked for. The same fix was applied to the keystroke
    // monitor in 887c86d (v2.9.1); that commit touched this file too but left
    // these six calls behind, and the audit on 2026-09-19 found them.

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
            selectionPopupLog.debug("checkSelection: no eligible frontmost app")
            onNoSelection()
            return
        }
        guard let (element, range) = TextCapture.captureFocusedSelectionRange(in: app) else {
            selectionPopupLog.debug("checkSelection: no selection range in app=\(app.localizedName ?? "?", privacy: .public)")
            onNoSelection()
            return
        }
        guard range.length >= Self.minimumSelectionLength else {
            selectionPopupLog.debug("checkSelection: range too short (\(range.length, privacy: .public) chars) in app=\(app.localizedName ?? "?", privacy: .public)")
            onNoSelection()
            return
        }
        guard let text = TextCapture.selectedText(from: element),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            selectionPopupLog.debug("checkSelection: range found but no text readable, app=\(app.localizedName ?? "?", privacy: .public)")
            onNoSelection()
            return
        }
        let bounds = TextCapture.boundsForSelection(element: element, range: range)
        selectionPopupLog.debug("checkSelection: match, \(text.count, privacy: .public) chars, bounds=\(bounds.map { "\($0)" } ?? "nil", privacy: .public), app=\(app.localizedName ?? "?", privacy: .public)")
        onSelection(SelectionSnapshot(
            text: text, element: element, range: range, bounds: bounds, sourceApp: app,
            nativeTextView: nil, nativeRange: nil
        ))
    }

    private func checkNativeSelection(in textView: NSTextView) {
        let range = textView.selectedRange()
        guard range.length >= Self.minimumSelectionLength else {
            selectionPopupLog.debug("checkNativeSelection: range too short (\(range.length, privacy: .public) chars)")
            onNoSelection()
            return
        }
        let text = (textView.string as NSString).substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onNoSelection()
            return
        }
        let bounds = textView.firstRect(forCharacterRange: range, actualRange: nil)
        selectionPopupLog.debug("checkNativeSelection: match, \(text.count, privacy: .public) chars in Notes editor")
        onSelection(SelectionSnapshot(
            text: text, element: nil, range: nil,
            bounds: bounds.isNull || bounds == .zero ? nil : bounds,
            sourceApp: nil, nativeTextView: textView, nativeRange: range
        ))
    }
}
