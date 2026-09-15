import SwiftUI

@main
struct TippiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.permissions)
                .environmentObject(appDelegate.hotkeyManager)
                .environmentObject(appDelegate.keyMonitor)
                // SnippetsTab and its consent sheet both require this. It used
                // to be reachable only by selecting the Snippets pane, which is
                // why the omission went unnoticed — the detail area now builds
                // every pane up front, so a missing object is a launch crash
                // rather than a crash on one specific click.
                .environmentObject(appDelegate.snippetStore)
        }
    }
}
