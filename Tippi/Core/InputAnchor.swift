import CoreGraphics

/// Where a panel that belongs to the text the user is working on opens — the
/// prompt popup (with or without a selection, including its dictation mode).
///
/// Pure geometry in AppKit screen coordinates (origin bottom-left, Y up), no
/// AppKit/AX dependency, so it is unit-testable without a window or a real
/// selection. The Accessibility reads live in `TextCapture.inputAnchorRects`.
///
/// Why (reported 2026-09-30): the popup opened at the mouse pointer. After
/// selecting text and pressing the hotkey the pointer is often somewhere else
/// entirely — the popup appeared in the bottom-right corner, far from the text.
enum InputAnchor {
    /// Gap between anchor and panel, and the inset kept from the screen edge.
    static let gap: CGFloat = 12
    static let edgeInset: CGFloat = 8

    /// The first plausible candidate, else the mouse (zero-size rect).
    /// `candidates` come best first — see `TextCapture.inputAnchorCandidates`:
    /// end of the selection (last character; for a long or multi-line selection
    /// that is where the eye is, not a huge rect), the whole selection, the caret.
    /// `screens` = full screen frames.
    static func anchor(candidates: [CGRect], mouse: CGPoint, screens: [CGRect]) -> CGRect {
        candidates.first { isPlausible($0, screens: screens) } ?? CGRect(origin: mouse, size: .zero)
    }

    /// Apps signal "no idea" in several ways — all measured in this codebase:
    /// an all-zero rect (Electron), a rect without height, a rect off every
    /// screen, a rect covering a whole text view. A caret has width 0 and is fine.
    static func isPlausible(_ rect: CGRect, screens: [CGRect]) -> Bool {
        guard !rect.isNull, !rect.isInfinite, rect.height > 0, rect.width >= 0,
              rect.origin != .zero else { return false }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = screens.first(where: { $0.contains(center) }) else { return false }
        return rect.height <= screen.height / 2
    }

    /// Panel origin: left edge at the anchor, just below it; above the anchor's
    /// TOP edge when there is no room below; always inside the visible frame of
    /// the screen holding the anchor. `visibleFrames` = `NSScreen.visibleFrame`s.
    static func origin(for anchor: CGRect, panelSize: CGSize, visibleFrames: [CGRect]) -> CGPoint {
        guard let frame = screen(for: anchor, in: visibleFrames) else {
            return CGPoint(x: anchor.minX, y: anchor.minY - gap - panelSize.height)
        }
        let minX = frame.minX + edgeInset, maxX = frame.maxX - edgeInset - panelSize.width
        let minY = frame.minY + edgeInset, maxY = frame.maxY - edgeInset - panelSize.height

        var y = anchor.minY - gap - panelSize.height
        if y < minY { y = anchor.maxY + gap }
        let x = maxX >= minX ? min(max(anchor.minX, minX), maxX) : minX
        if maxY >= minY { y = min(max(y, minY), maxY) }
        return CGPoint(x: x, y: y)
    }

    /// The visible frame containing the anchor; for an anchor in the menu bar
    /// or Dock strip (inside a screen, outside its visible frame) the nearest one.
    private static func screen(for anchor: CGRect, in frames: [CGRect]) -> CGRect? {
        let point = CGPoint(x: anchor.minX, y: anchor.midY)
        if let hit = frames.first(where: { $0.contains(point) }) { return hit }
        return frames.min { distance(point, $0) < distance(point, $1) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
