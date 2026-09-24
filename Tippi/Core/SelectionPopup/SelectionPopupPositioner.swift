import CoreGraphics

/// Where the action bar appears relative to the text selection — configurable
/// so it can be moved out of the way of another app's own selection popup
/// (Safari's "Look Up", Pages' floating toolbar, etc.) instead of colliding
/// with it.
enum SelectionPopupPosition: String, CaseIterable, Identifiable {
    case below, above, right, left

    var id: String { rawValue }

    /// The side tried automatically when this one doesn't have room —
    /// below/above compete for vertical space, left/right for horizontal,
    /// so each one's natural fallback is its counterpart on the same axis.
    var opposite: SelectionPopupPosition {
        switch self {
        case .below: return .above
        case .above: return .below
        case .right: return .left
        case .left: return .right
        }
    }
}

/// Pure geometry — given the selection's on-screen bounds (AppKit screen
/// coordinates: origin bottom-left, Y increasing upward) and the popup's
/// size, computes where to place it, then clamps the result to stay on
/// screen. No AppKit/AX dependency, so this is fully unit-testable without
/// a real window or a real text selection.
enum SelectionPopupPositioner {
    /// Gap between the selection and the popup, and the inset kept from the
    /// screen edge when clamping — same value for both, no strong reason to
    /// differ. 16pt, not 8: at 8 the bar visually overlapped the selected
    /// line in real-world testing — text line height plus anti-aliasing
    /// margin needs more clearance than it looks like on paper.
    static let gap: CGFloat = 16

    /// How far the pointer may stray before the bar closes, measured from the
    /// area covered by the bar AND the selection together — not from the bar
    /// alone: at the end of a long selected line the pointer can already sit
    /// hundreds of points from a bar centred on that line, and a bar-only
    /// distance would close it before it could ever be reached. ~3 cm on a
    /// typical display: far enough to not fire while reaching for a button,
    /// near enough that moving on to other work closes it at once.
    static let dismissDistance: CGFloat = 100

    /// True when `pointer` has moved more than `distance` outside the area
    /// covered by `popupFrame` and `selectionBounds`. `selectionBounds` may be
    /// a zero-size rect (the mouse-position fallback when an app reports no
    /// usable bounds) — it still counts as a point inside the zone.
    static func pointerHasLeft(
        _ pointer: CGPoint,
        popupFrame: CGRect,
        selectionBounds: CGRect,
        distance: CGFloat = dismissDistance
    ) -> Bool {
        // `union` keeps a zero-size (non-null) rect as a point — pinned by a test.
        let zone = popupFrame.union(selectionBounds).insetBy(dx: -distance, dy: -distance)
        return !zone.contains(pointer)
    }

    /// True when `pointer` sits on the selection itself (plus a few points of
    /// slack for the edge of a glyph). Used to tell a deliberate re-selection —
    /// the drag or double-click ends on the text — from a click elsewhere that
    /// merely left an old selection intact.
    static func pointerIsOnSelection(
        _ pointer: CGPoint,
        selectionBounds: CGRect,
        tolerance: CGFloat = 4
    ) -> Bool {
        selectionBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(pointer)
    }

    static func origin(
        for selectionBounds: CGRect,
        popupSize: CGSize,
        position: SelectionPopupPosition,
        screenFrame: CGRect
    ) -> CGPoint {
        let preferred = rawOrigin(for: selectionBounds, popupSize: popupSize, position: position)
        if fitsWithoutClamping(preferred, size: popupSize, in: screenFrame) {
            return preferred
        }

        // The preferred side doesn't have room (e.g. a selection near the
        // top of the screen with position=.above) — plain clamping would
        // push the popup back down onto the selection itself, which is
        // exactly the overlap bug this fallback exists to avoid. Try the
        // opposite side first; only clamp in place if neither side fits
        // (a genuinely tiny screen/window).
        let alternate = rawOrigin(for: selectionBounds, popupSize: popupSize, position: position.opposite)
        if fitsWithoutClamping(alternate, size: popupSize, in: screenFrame) {
            return alternate
        }

        return clamp(preferred, size: popupSize, in: screenFrame)
    }

    private static func rawOrigin(
        for selectionBounds: CGRect,
        popupSize: CGSize,
        position: SelectionPopupPosition
    ) -> CGPoint {
        switch position {
        case .below:
            // "Below" on screen = smaller Y in AppKit's bottom-left-origin
            // coordinate system, not larger.
            return CGPoint(
                x: selectionBounds.midX - popupSize.width / 2,
                y: selectionBounds.minY - gap - popupSize.height
            )
        case .above:
            return CGPoint(
                x: selectionBounds.midX - popupSize.width / 2,
                y: selectionBounds.maxY + gap
            )
        case .right:
            return CGPoint(
                x: selectionBounds.maxX + gap,
                y: selectionBounds.midY - popupSize.height / 2
            )
        case .left:
            return CGPoint(
                x: selectionBounds.minX - gap - popupSize.width,
                y: selectionBounds.midY - popupSize.height / 2
            )
        }
    }

    private static func fitsWithoutClamping(_ point: CGPoint, size: CGSize, in screenFrame: CGRect) -> Bool {
        let rect = CGRect(origin: point, size: size)
        return screenFrame.insetBy(dx: gap, dy: gap).contains(rect)
    }

    /// Last-resort fallback so the popup never opens partly off-screen, even
    /// when no side has enough room.
    private static func clamp(_ point: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        var clamped = point
        let minX = screenFrame.minX + gap
        let maxX = screenFrame.maxX - gap - size.width
        let minY = screenFrame.minY + gap
        let maxY = screenFrame.maxY - gap - size.height

        if maxX >= minX { clamped.x = min(max(clamped.x, minX), maxX) }
        if maxY >= minY { clamped.y = min(max(clamped.y, minY), maxY) }
        return clamped
    }
}
