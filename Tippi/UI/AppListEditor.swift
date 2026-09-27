import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App-Liste für die Einstellungen: zeigt Symbol und Namen statt der Bundle-ID
/// und fügt Apps über ein Menü hinzu (laufende Apps oder „Andere App wählen…“).
/// Genutzt von der Ausschlussliste der Autovervollständigung und von „Enter nach
/// Diktat“ — vorher zwei Kopien mit Bundle-ID-Textfeld (2026-09-27).
struct AppListEditor: View {
    let bundleIDs: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bundleIDs, id: \.self) { bundleID in
                let app = AppInfo(bundleID: bundleID)
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(app.name)
                    if !app.isInstalled {
                        Text(String(localized: "settings.appList.notInstalled"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onRemove(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "settings.autocomplete.remove"))
                }
                .help(bundleID)
            }
            Menu(String(localized: "settings.autocomplete.addRunningApp")) {
                ForEach(runningApps, id: \.bundleID) { app in
                    Button {
                        onAdd(app.bundleID)
                    } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                    }
                }
                if !runningApps.isEmpty { Divider() }
                Button(String(localized: "settings.appList.chooseOther")) { chooseApp() }
            }
            .fixedSize()
        }
    }

    /// Laufende Apps mit Fenster, ohne Tippi und ohne bereits eingetragene.
    private var runningApps: [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleIdentifier }
            .filter { $0 != Bundle.main.bundleIdentifier && !bundleIDs.contains($0) }
            .map { AppInfo(bundleID: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Für Apps, die gerade nicht laufen: Auswahl im Programme-Ordner.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        onAdd(bundleID)
    }
}

/// Name und Symbol einer App zur Bundle-ID. Nicht installierte Apps behalten die
/// Bundle-ID als Namen — die Voreinstellungen enthalten Apps, die nicht jeder hat.
struct AppInfo {
    let bundleID: String
    let name: String
    let icon: NSImage
    let isInstalled: Bool

    init(bundleID: String) {
        self.bundleID = bundleID
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            image = NSWorkspace.shared.icon(forFile: url.path)
            isInstalled = true
        } else {
            name = bundleID
            image = NSWorkspace.shared.icon(for: .applicationBundle)
            isInstalled = false
        }
        // Kopie: das Symbol kann ein geteiltes Objekt sein; die Größe gilt fürs Menü.
        icon = (image.copy() as? NSImage) ?? image
        icon.size = NSSize(width: 16, height: 16)
    }
}
