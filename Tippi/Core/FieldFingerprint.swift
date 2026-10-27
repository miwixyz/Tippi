import CoreGraphics

/// Which text field a dictation goes into (2026-10-27). Taken when the
/// recording ends and compared right before inserting: if the user clicked
/// into another field of the same app while Tippi transcribed (Mail: subject
/// instead of body), the text goes to the clipboard instead of the wrong
/// place. The app-level check (`TextInsertion.isExpectedFrontmost`, PID)
/// stays in front of this one.
///
/// Idea from Blitztext (`AppState.swift`, role + position, MIT, NOTICES.md).
/// Differences, on purpose:
/// - Position relative to the window, not to the screen: dragging the window
///   while Tippi transcribes keeps the same field.
/// - A tolerance instead of exact equality, see `tolerance`.
/// - Only a *proven* different field blocks. Where the app does not report
///   enough to tell (no role, no position), the text goes in as before — the
///   check must never break an insertion that worked without it.
struct FieldFingerprint: Equatable {
    var role: String?
    /// Top-left of the field minus top-left of its window (AX coordinates).
    var offsetInWindow: CGPoint?
    /// Top-left on screen — used only when a window offset is missing on
    /// either side.
    var screenPosition: CGPoint?

    /// How far a field may move and still count as the same one, in points per
    /// axis. 8 pt is above what a re-layout does to an unchanged field (focus
    /// ring, a 1–3 pt border change, half-point rounding on Retina, an app that
    /// rebuilt its accessibility objects) and well below the gap between two
    /// stacked one-line fields (Mail's To/Subject rows, form fields: ≥ 20 pt).
    /// So the error it accepts is the harmless one: a field that really moved
    /// further (a banner pushed it down, a chat box grew) sends the text to the
    /// clipboard — annoying, recoverable with ⌘V — instead of risking text in
    /// the wrong field.
    static let tolerance: CGFloat = 8

    /// `sameElement`: `CFEqual` of the two AX elements. True settles it — the
    /// position may have changed (a text view scrolls with its content).
    static func isSameField(_ start: FieldFingerprint, _ now: FieldFingerprint, sameElement: Bool) -> Bool {
        if sameElement { return true }
        if let a = start.role, let b = now.role, a != b { return false }
        if let a = start.offsetInWindow, let b = now.offsetInWindow {
            return close(a, b)
        }
        if let a = start.screenPosition, let b = now.screenPosition {
            return close(a, b)
        }
        return true   // nothing to compare: cannot prove another field
    }

    private static func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }
}
