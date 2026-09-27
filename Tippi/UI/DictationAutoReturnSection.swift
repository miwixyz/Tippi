import AppKit
import SwiftUI

/// Einstellungen → Sprache: Apps, in denen Tippi nach einem Diktat Enter drückt.
/// Leere Liste = Funktion aus (ab Werk). Die Liste bedient dieselben Bedienelemente
/// wie die Ausschlussliste der Autovervollständigung.
struct DictationAutoReturnSection: View {
    @State private var apps: [String] = DictationSettings.autoReturnBundleIDs
    @State private var newBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.voice.dictation.autoReturn.title"))
                .font(.subheadline)
            Text(String(localized: "settings.voice.dictation.autoReturn.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if apps.isEmpty {
                Text(String(localized: "settings.voice.dictation.autoReturn.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(apps, id: \.self) { bundleID in
                HStack {
                    Text(Self.displayName(for: bundleID))
                    Text(bundleID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        save(apps.filter { $0 != bundleID })
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "settings.autocomplete.remove"))
                }
            }
            HStack {
                Menu(String(localized: "settings.autocomplete.addRunningApp")) {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                }
                .fixedSize()
                TextField(String(localized: "settings.autocomplete.bundleIDPlaceholder"), text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add(newBundleID) }
                Button(String(localized: "settings.autocomplete.add")) { add(newBundleID) }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private struct RunningApp { let name: String; let bundleID: String }

    /// Laufende Apps mit Fenster, ohne Tippi und ohne bereits eingetragene.
    private var runningApps: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !apps.contains(id) else { return nil }
                return RunningApp(name: app.localizedName ?? id, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// App-Name statt nackter Bundle-ID — fällt auf die ID zurück, wenn die App
    /// auf diesem Mac nicht installiert ist.
    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func add(_ bundleID: String) {
        save(apps + [bundleID])
        newBundleID = ""
    }

    private func save(_ list: [String]) {
        DictationSettings.autoReturnBundleIDs = list
        apps = DictationSettings.autoReturnBundleIDs
    }
}
