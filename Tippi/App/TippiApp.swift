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
        }
    }
}
