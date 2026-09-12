import Foundation

/// Persisted settings for the Notes window's global hotkey — same shape as
/// `TranslateSettings`/`EmojiSettings` (enable toggle + remappable combo),
/// wired into `AppDelegate.restartNotesHotkey()` from Settings → Hotkeys.
@MainActor
enum NotesSettings {
    private static let enabledKey = "notes.hotkey.enabled"
    private static let comboKey = "notes.hotkeyCombo.v1"

    /// On by default — like Translate/Emoji, Notes has no setup prerequisite
    /// (no model download, no permission beyond what Tippi already has).
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = UserDefaults.standard.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .notesDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: comboKey)
            }
        }
    }
}
