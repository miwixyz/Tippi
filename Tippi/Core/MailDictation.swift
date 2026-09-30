import Foundation

/// „Diktat für Mails": eigener Hotkey, gleiches Diktat, aber `DictationLayout` immer an
/// (`DictationSource.mail`). Registriert in `AppDelegate.restartMailDictationHotkey`,
/// nur solange das normale Diktat an und die Sprach-Engine bereit ist.
@MainActor
enum MailDictationSettings {
    private static let enabledKey = "dictation.mailHotkey.enabled.v1"
    private static let comboKey = "dictation.mailHotkeyCombo.v1"

    /// ⌃⌥⌘B — B für Brief. Kollidiert mit keinem Tippi-Standard (⌥⌘T, ⌃⌥⌘T, ⌃⌥⌘M,
    /// ⌥⌘L, ⌥⌘E, ⌥⌘N, ⌥⌘2) und ist ab Werk kein macOS-Kürzel.
    static let defaultCombo = KeyCombo(keyCode: 11, modifiers: [.control, .option, .command])
    /// Tippis fest eingebauter Sicherheits-Hotkey (`registerSafetyHotKey`).
    static let safetyCombo = KeyCombo(keyCode: 17, modifiers: [.control, .option, .command])

    /// An, sobald das Diktat an ist — der Hotkey ist die ganze Funktion.
    static var isEnabled: Bool {
        get { DictationSettings.store.object(forKey: enabledKey) as? Bool ?? true }
        set { DictationSettings.store.set(newValue, forKey: enabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = DictationSettings.store.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return defaultCombo }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { DictationSettings.store.set(data, forKey: comboKey) }
        }
    }

    /// Name des Kürzels, das `combo` schon belegt — oder `nil`, wenn frei.
    static func conflict(of combo: KeyCombo, in taken: [(name: String, combo: KeyCombo)]) -> String? {
        taken.first { $0.combo == combo }?.name
    }

    /// Alle anderen Tippi-Kürzel, gegen die geprüft wird (auch ausgeschaltete —
    /// wer sie später einschaltet, soll keinen stillen Doppelgänger bekommen).
    static func takenCombos() -> [(name: String, combo: KeyCombo)] {
        var taken: [(name: String, combo: KeyCombo)] = [
            (String(localized: "hotkeyName.main"), KeyComboStore.load()),
            (String(localized: "hotkeyName.safety"), safetyCombo),
            (String(localized: "hotkeyName.translate"), TranslateSettings.combo),
            (String(localized: "hotkeyName.emoji"), EmojiSettings.combo),
            (String(localized: "hotkeyName.notes"), NotesSettings.combo),
            (String(localized: "hotkeyName.screenOCR"), ScreenOCRSettings.combo),
        ]
        if DictationSettings.mode == .combo {
            taken.append((String(localized: "hotkeyName.dictation"), DictationSettings.combo))
        }
        return taken
    }
}
