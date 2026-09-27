import SwiftUI

@main
struct TippiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty on purpose. The real Settings window is AppDelegate's own
        // (`showSettingsWindow`). A SwiftUI Settings scene with a second
        // SettingsView opened through the standard "Settings… ⌘," item while
        // Notes made the app `.regular` — two windows, two independent sets of
        // @State, one stale (audit 2026-09-27). The command is routed to the
        // one window instead.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "menu.settings")) {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
