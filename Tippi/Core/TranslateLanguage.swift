import Foundation

/// Languages selectable in the Translate Quick Panel's source/target
/// dropdowns. Kept to the same small, deliberately curated set as the
/// dictation language picker (`AppDelegate.dictationLanguages`) rather than
/// every language a translation model could theoretically handle — this is
/// a quick panel, not a full translator UI.
enum TranslateLanguage: String, CaseIterable, Identifiable {
    case auto
    case german
    case english
    case spanish
    case french
    case japanese

    var id: String { rawValue }

    /// Shown in the UI, in the language's own script — matches how the
    /// dictation language menu already labels these.
    var displayName: String {
        switch self {
        case .auto: return String(localized: "settings.voice.language.auto")
        case .german: return "Deutsch"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .japanese: return "日本語"
        }
    }

    /// English name for the LLM instruction — translation prompts are more
    /// reliable in English regardless of the pair being translated (this
    /// mirrors the original hardcoded "German"/"Spanish" wording).
    var englishName: String {
        switch self {
        case .auto: return "auto-detected language"
        case .german: return "German"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .japanese: return "Japanese"
        }
    }

    /// Target must always be a concrete language — "auto-detect" as an
    /// output makes no sense, so it's excluded from that picker's options.
    static var targetOptions: [TranslateLanguage] {
        allCases.filter { $0 != .auto }
    }
}
