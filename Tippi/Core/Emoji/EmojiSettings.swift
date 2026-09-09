import Foundation

/// Persisted settings for the emoji picker and `:name:` inline expansion.
///
/// Unlike the selection action bar (ambient, fires on every text selection,
/// therefore opt-in), inline emoji expansion only reacts to a deliberate
/// `:word:` sequence that has to match a known emoji name — so it ships ON.
/// An unknown name is left completely untouched, which makes an accidental
/// trigger close to impossible; see `EmojiInlineMatcher` for the guards.
@MainActor
enum EmojiSettings {
    private static let pickerEnabledKey = "emoji.picker.enabled.v1"
    private static let inlineEnabledKey = "emoji.inline.enabled.v1"
    private static let emoticonEnabledKey = "emoji.emoticon.enabled.v1"
    private static let comboKey = "emoji.hotkeyCombo.v1"
    private static let recentsKey = "emoji.recents.v1"

    static let maxRecents = 30

    /// Hotkey-opened picker. On by default — an explicit key combo has no
    /// ambient side effects. (`object(forKey:) as? Bool ?? true` rather than
    /// `bool(forKey:)`, which cannot tell "user switched it off" from "never
    /// set" and would silently default the feature to off.)
    static var isPickerEnabled: Bool {
        get { UserDefaults.standard.object(forKey: pickerEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: pickerEnabledKey) }
    }

    /// `:rakete:` → 🚀 while typing, anywhere on the Mac.
    static var isInlineEnabled: Bool {
        get { UserDefaults.standard.object(forKey: inlineEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: inlineEnabledKey) }
    }

    /// `:-)` → 🙂 while typing. Independent of `isInlineEnabled` on purpose:
    /// emoticons have no closing delimiter, so they carry a different (small
    /// but real) false-positive risk than `:name:` does. Turning this off
    /// leaves the `:name:` shortcodes and the picker untouched.
    static var isEmoticonEnabled: Bool {
        get { UserDefaults.standard.object(forKey: emoticonEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: emoticonEnabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = UserDefaults.standard.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .emojiDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: comboKey)
            }
        }
    }

    /// Most recently inserted emoji, newest first — shown when the picker's
    /// search field is empty, because the same handful of emoji make up most
    /// of anyone's real usage.
    static var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentsKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(maxRecents)), forKey: recentsKey) }
    }

    static func rememberUse(of character: String) {
        var list = recents
        list.removeAll { $0 == character }
        list.insert(character, at: 0)
        recents = list
    }

    static func clearRecents() {
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }
}
