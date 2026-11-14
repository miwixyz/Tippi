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

    // MARK: Sprachnotiz (Michael 2026-11-14, docs/SECURE-DESIGN-sprachnotiz.md)

    private static let voiceEnabledKey = "notes.voiceHotkey.enabled"
    private static let voiceComboKey = "notes.voiceHotkeyCombo.v1"
    private static let opacityKey = "notes.quickNotes.opacity.v1"

    /// Kürzel: Schnellnotiz-Panel zeigen und sofort diktieren, Text geht an „Eingang“. Ab Werk an.
    static var isVoiceEnabled: Bool {
        get { store.object(forKey: voiceEnabledKey) as? Bool ?? true }
        set { store.set(newValue, forKey: voiceEnabledKey) }
    }

    static var voiceCombo: KeyCombo {
        get {
            guard let data = store.data(forKey: voiceComboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .voiceNoteDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: voiceComboKey)
            }
        }
    }

    /// Deckkraft des Schnellnotiz-Panels. Begrenzt: bei 0 wäre es unsichtbar und nicht mehr bedienbar.
    static let opacityRange: ClosedRange<Double> = 0.35...1.0
    static var quickNotesOpacity: Double {
        get { clampedOpacity(store.object(forKey: opacityKey)) }
        set { store.set(clampedOpacity(newValue), forKey: opacityKey) }
    }

    /// Gespeicherte Werte können per `defaults write` Unsinn sein – nur endliche Zahlen im Bereich.
    nonisolated static func clampedOpacity(_ raw: Any?) -> Double {
        guard let value = (raw as? NSNumber)?.doubleValue, value.isFinite else { return 1.0 }
        return min(max(value, 0.35), 1.0)
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
    /// Posted after `NotesRootView.requestSelection(of:)` — selects that note.
    static let selectNote = Notification.Name("TippiSelectNote")
}
