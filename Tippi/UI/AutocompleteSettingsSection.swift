import AppKit
import SwiftUI

/// Einstellungen → Allgemein: Labs-Schalter „Autovervollständigung beim Tippen"
/// mit Datenschutz-Erklärung, Server-Hinweis und Ausschlussliste.
/// Sicherheitsdesign: `docs/SECURE-DESIGN-autocomplete.md`.
struct AutocompleteSettingsSection: View {
    @ObservedObject var controller: AutocompleteController
    @ObservedObject private var mlx = MLXServerManager.shared
    @State private var excluded: [String] = AutocompleteSettings.excludedBundleIDs

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
            // `try?` below swallows the start error — the manager keeps it in
            // `state`, so show it here instead of a button that just re-enables
            // (audit 2026-09-27).
            if case .failed(let message) = mlx.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            AppListEditor(
                bundleIDs: excluded,
                onAdd: { bundleID in
                    AutocompleteSettings.addExclusion(bundleID)
                    excluded = AutocompleteSettings.excludedBundleIDs
                },
                onRemove: { bundleID in
                    AutocompleteSettings.removeExclusion(bundleID)
                    excluded = AutocompleteSettings.excludedBundleIDs
                }
            )
        }
    }
}
