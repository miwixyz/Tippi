import Foundation

/// Persisted settings for the Notes window's global hotkey — same shape as
/// `TranslateSettings`/`EmojiSettings` (enable toggle + remappable combo),
/// wired into `AppDelegate.restartNotesHotkey()` from Settings → Hotkeys.
@MainActor
enum NotesSettings {
    /// See `DictationSettings.store`: `.standard` in the app, a throwaway suite in
    /// tests — the test host shares the installed app's preferences file.
    static var store: UserDefaults = .standard
    private static let enabledKey = "notes.hotkey.enabled"
    private static let comboKey = "notes.hotkeyCombo.v1"
    private static let sidebarKey = "notes.sidebarVisible.v1"

    /// On by default — like Translate/Emoji, Notes has no setup prerequisite
    /// (no model download, no permission beyond what Tippi already has).
    static var isEnabled: Bool {
        get { store.object(forKey: enabledKey) as? Bool ?? true }
        set { store.set(newValue, forKey: enabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = store.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .notesDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: comboKey)
            }
        }
    }

    /// Note list shown next to the editor (⌃⌘S, like Apple Notes). Shown by
    /// default. Local to this Mac on purpose — screen sizes differ between Macs,
    /// so it does not go through `NotesPreferences` (iCloud).
    static var isSidebarVisible: Bool {
        get { store.object(forKey: sidebarKey) as? Bool ?? true }
        set { store.set(newValue, forKey: sidebarKey) }
    }
}

extension Notification.Name {
    /// Posted by the menu command „Seitenleiste ein-/ausblenden" (⌃⌘S);
    /// `NotesRootView` toggles its list column.
    static let toggleNotesSidebar = Notification.Name("TippiToggleNotesSidebar")
}
