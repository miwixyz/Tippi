import Foundation

/// Persisted settings for the Translate Quick Panel — a Spotlight-style
/// "type text, get translation" window. Its hotkey now captures the current
/// selection if there is one (see `AppDelegate.toggleTranslatePanel`), but
/// still works with nothing selected — typing, pasting, or dictating into
/// the field all remain valid, unlike the main hotkey flow which requires a
/// selection.
@MainActor
enum TranslateSettings {
    private static let enabledKey = "translate.enabled"
    private static let comboKey   = "translate.hotkeyCombo.v1"
    private static let sourceLanguageKey = "translate.sourceLanguage.v1"
    private static let targetLanguageKey = "translate.targetLanguage.v1"

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

    /// Source defaults to auto-detect — most inputs don't need the user to
    /// name the language they're typing in.
    static var sourceLanguage: TranslateLanguage {
        get {
            TranslateLanguage(rawValue: UserDefaults.standard.string(forKey: sourceLanguageKey) ?? "") ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sourceLanguageKey) }
    }

    /// Target defaults to Spanish — Michael's primary use case (Cati, Costa
    /// Rica). The swap control in the panel makes flipping direction a
    /// one-click action rather than requiring two dropdown changes.
    static var targetLanguage: TranslateLanguage {
        get {
            TranslateLanguage(rawValue: UserDefaults.standard.string(forKey: targetLanguageKey) ?? "") ?? .spanish
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: targetLanguageKey) }
    }

    /// Builds the translation instruction for the current source/target
    /// pair. Auto-source just asks for detection; an explicit source names
    /// it directly, which is both a stronger hint to the model and lets the
    /// user force a direction the auto-detector might get wrong on short/
    /// ambiguous input.
    static func systemPrompt(source: TranslateLanguage, target: TranslateLanguage) -> String {
        let sourceInstruction = source == .auto
            ? "Detect the input language automatically."
            : "The input is in \(source.englishName)."
        return """
        You are a translation tool. \(sourceInstruction) Translate it into natural, modern \(target.englishName).
        Return ONLY the translation. No explanation, no quotes, no language label, no commentary.
        """
    }
}
