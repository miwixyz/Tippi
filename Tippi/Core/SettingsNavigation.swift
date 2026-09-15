import Combine

enum SettingsTab: Hashable, CaseIterable {
    case general, hotkeys, providers, prompts, snippets, voice, history, help, about

    /// Title and symbol live on the case rather than at the call site so the
    /// sidebar row and the window title cannot drift apart.
    var title: String {
        switch self {
        case .general:   return String(localized: "settings.tab.general")
        case .hotkeys:   return String(localized: "settings.tab.hotkeys")
        case .providers: return String(localized: "settings.tab.providers")
        case .prompts:   return String(localized: "settings.tab.prompts")
        case .snippets:  return String(localized: "settings.tab.snippets")
        case .voice:     return String(localized: "settings.tab.voice")
        case .history:   return String(localized: "settings.tab.history")
        case .help:      return String(localized: "settings.tab.help")
        case .about:     return String(localized: "settings.tab.about")
        }
    }

    var symbol: String {
        switch self {
        case .general:   return "gear"
        case .hotkeys:   return "command"
        case .providers: return "key"
        case .prompts:   return "text.bubble"
        case .snippets:  return "text.badge.checkmark"
        case .voice:     return "mic"
        case .history:   return "clock.arrow.circlepath"
        case .help:      return "questionmark.circle"
        case .about:     return "info.circle"
        }
    }
}

/// Lets an action outside `SettingsView` (menu bar items, for now) jump
/// straight to a specific tab instead of just opening Settings on whatever
/// tab was last selected. The Settings window is created once and then only
/// reordered front on repeat opens (`AppDelegate.showSettingsWindow`), so
/// `SettingsView` never gets a fresh `.onAppear` to react to on later opens —
/// this publishes the request instead, which `SettingsView` observes for the
/// life of the window via `.onReceive`.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var pendingTab: SettingsTab?
    private init() {}
}
