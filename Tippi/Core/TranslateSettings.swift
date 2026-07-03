import Foundation

/// Persisted settings for the Translate Quick Panel — a Spotlight-style
/// "type text, get translation" window. Independent of the main hotkey flow
/// (which transforms *selected* text in another app); this one has no
/// dependency on AX capture or a source selection at all.
@MainActor
enum TranslateSettings {
    private static let enabledKey = "translate.enabled"
    private static let comboKey   = "translate.hotkeyCombo.v1"

    /// On by default — unlike dictation, this has no setup prerequisite
    /// (no model download), so there is no reason to start it disabled.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = UserDefaults.standard.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .translateDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: comboKey)
            }
        }
    }

    /// Auto-direction DE↔ES: detects the input language and translates to the
    /// other one — no language picker in the UI. Falls back to German for any
    /// other detected language so the panel never just echoes the input back.
    static let systemPrompt = """
    You are a translation tool. Detect whether the input text is German or Spanish.
    - If German, translate it to natural, modern Spanish.
    - If Spanish, translate it to natural, modern German.
    - If the language is ambiguous or neither German nor Spanish, translate it to German.
    Return ONLY the translation. No explanation, no quotes, no language label, no commentary.
    """
}
