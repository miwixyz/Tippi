import Combine

enum SettingsTab: Hashable {
    case general, hotkeys, providers, prompts, snippets, voice, history, help, about
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
