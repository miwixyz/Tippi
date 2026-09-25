import AppKit
import SwiftUI

/// Einstellungen → Allgemein: Labs-Schalter „Autovervollständigung beim Tippen"
/// mit Datenschutz-Erklärung, Server-Hinweis und Ausschlussliste.
/// Sicherheitsdesign: `docs/SECURE-DESIGN-autocomplete.md`.
struct AutocompleteSettingsSection: View {
    @ObservedObject var controller: AutocompleteController
    @ObservedObject private var mlx = MLXServerManager.shared
    @State private var excluded: [String] = AutocompleteSettings.excludedBundleIDs
    @State private var newBundleID = ""

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { controller.isEnabled },
                set: { AppDelegate.shared?.setAutocompleteEnabled($0) }
            )) {
                HStack(spacing: 6) {
                    Text(String(localized: "settings.autocomplete.toggle"))
                    Text("Labs")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
            }
            Text(String(localized: "settings.autocomplete.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if controller.isEnabled {
                if let error = controller.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if mlx.ownedServerURL == nil {
                    serverHint
                }
                exclusionList
            }
        }
    }

    /// Ohne selbst gestarteten Server keine Vorschläge — und der Weg dorthin.
    @ViewBuilder private var serverHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.autocomplete.noServer"))
                .font(.caption)
                .foregroundStyle(.orange)
            HStack {
                if MLXServerManager.isInstalled {
                    Button(String(localized: "settings.autocomplete.startServer")) {
                        Task { try? await MLXServerManager.shared.start() }
                    }
                    .disabled(mlx.state == .starting)
                }
                Button(String(localized: "settings.autocomplete.openProviders")) {
                    SettingsNavigation.shared.pendingTab = .providers
                }
            }
        }
    }

    @ViewBuilder private var exclusionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.autocomplete.excluded"))
                .font(.subheadline)
            ForEach(excluded, id: \.self) { bundleID in
                HStack {
                    Text(bundleID).font(.system(.caption, design: .monospaced))
                    Spacer()
                    Button {
                        AutocompleteSettings.removeExclusion(bundleID)
                        excluded = AutocompleteSettings.excludedBundleIDs
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

    /// Laufende Apps mit Fenster, ohne Tippi und ohne bereits ausgeschlossene.
    private var runningApps: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !excluded.contains(id) else { return nil }
                return RunningApp(name: app.localizedName ?? id, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ bundleID: String) {
        AutocompleteSettings.addExclusion(bundleID)
        excluded = AutocompleteSettings.excludedBundleIDs
        newBundleID = ""
    }
}
