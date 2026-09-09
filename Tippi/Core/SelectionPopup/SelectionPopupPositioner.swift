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
