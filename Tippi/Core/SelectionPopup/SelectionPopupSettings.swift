import Foundation

/// Persisted settings for the selection action bar — the PopClip-style
/// toolbar that appears automatically next to a text selection anywhere on
/// the Mac. Off by default: an ambient system-wide popup on every text
/// selection is a much bigger behavioral change than an explicit hotkey,
/// and some apps already show their own selection toolbar (Safari's "Look
/// Up", Pages' floating formatting bar) — this needs an opt-in, not a
/// surprise after an update.
@MainActor
enum SelectionPopupSettings {
    static let enabledKey = "selectionPopup.enabled"
    private static let positionKey = "selectionPopup.position.v1"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Where the bar appears relative to the selection — configurable
    /// specifically so it can be moved out of the way of another app's own
    /// selection popup instead of stacking on top of it.
    static var position: SelectionPopupPosition {
        get {
            SelectionPopupPosition(rawValue: UserDefaults.standard.string(forKey: positionKey) ?? "") ?? .below
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: positionKey) }
    }
}
