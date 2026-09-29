import AppKit
import SwiftUI

/// Einstellungen → Autovervollständigung (Labs): Schalter mit Datenschutz-
/// Erklärung, verwendetes Modell, die zwei Übernahme-Tasten, Tastenhinweis und
/// Ausschlussliste. Bis 2026-09-28 ein Abschnitt unter „Allgemein".
/// Sicherheitsdesign: `docs/SECURE-DESIGN-autocomplete.md`.
struct AutocompleteSettingsTab: View {
    @ObservedObject var controller: AutocompleteController
    @ObservedObject private var mlx = MLXServerManager.shared
    @State private var excluded: [String] = AutocompleteSettings.excludedBundleIDs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox { toggleSection.padding(6) }
                GroupBox { modelSection.padding(6) }
                GroupBox { AutocompleteKeysSection(controller: controller).padding(6) }
                GroupBox { exclusionList.padding(6) }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { controller.isEnabled },
                set: { AppDelegate.shared?.setAutocompleteEnabled($0) }
            )) {
                HStack(spacing: 6) {
                    Text(String(localized: "settings.autocomplete.toggle"))
                        .font(FamilyTheme.font(.headline))
                    Text("Labs")
                        .font(FamilyTheme.font(.caption2, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
            }
            Text(String(localized: "settings.autocomplete.hint"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.isEnabled, let error = controller.lastError {
                Text(error).font(FamilyTheme.font(.caption)).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Welches Modell die Vorschläge macht — immer Tippis eigener MLX-Server,
    /// auch wenn der Standard-Anbieter ein anderer ist.
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.autocomplete.model.title"))
                .font(FamilyTheme.font(.headline))
            HStack(spacing: 8) {
                Text(String(format: String(localized: "settings.autocomplete.model.current"),
                            MLXServerManager.activeModel))
                    .font(FamilyTheme.font(.callout))
                    .textSelection(.enabled)
                Spacer()
                Button(String(localized: "settings.autocomplete.model.change")) {
                    SettingsNavigation.shared.openProvider("mlx")
                }
            }
            Text(String(localized: "settings.autocomplete.model.hint"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.isEnabled, mlx.ownedServerURL == nil {
                serverHint
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ohne selbst gestarteten Server keine Vorschläge — und der Weg dorthin.
    @ViewBuilder private var serverHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.autocomplete.noServer"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.orange)
            // `try?` below swallows the start error — the manager keeps it in
            // `state`, so show it here instead of a button that just re-enables
            // (audit 2026-09-27).
            if case .failed(let message) = mlx.state {
                Text(message)
                    .font(FamilyTheme.font(.caption))
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
                    SettingsNavigation.shared.openProvider("mlx")
                }
            }
        }
    }

    @ViewBuilder private var exclusionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.autocomplete.excluded"))
                .font(FamilyTheme.font(.headline))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Die zwei frei belegbaren Übernahme-Tasten + Tastenhinweis. Welche Tasten
/// erlaubt sind, entscheidet `AutocompleteKeyRules` (rein, getestet); der
/// Recorder zeigt den Grund, wenn eine Taste abgelehnt wird. Dieselbe Taste
/// für beide Aktionen tauscht (`AutocompleteKeyBindings.assigning`).
private struct AutocompleteKeysSection: View {
    let controller: AutocompleteController
    @State private var bindings = AutocompleteSettings.keyBindings
    @State private var showKeyHint = AutocompleteSettings.showKeyHint
    /// Kurzer Hinweis nach einem automatischen Tausch.
    @State private var swapNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.autocomplete.keys.title"))
                .font(FamilyTheme.font(.headline))
            Text(String(localized: "settings.autocomplete.keys.hint"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            keyRow(String(localized: "settings.autocomplete.keys.nextWord"), action: .nextWord)
            keyRow(String(localized: "settings.autocomplete.keys.whole"), action: .wholeSuggestion)

            if swapNotice {
                Text(String(localized: "settings.autocomplete.keys.swapped"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(String(localized: "settings.autocomplete.keys.reset")) {
                    bindings = .default
                    swapNotice = false
                }
                .buttonStyle(.bordered)
                .disabled(bindings == .default)
                Spacer()
            }

            Toggle(String(localized: "settings.autocomplete.keys.showHint"), isOn: $showKeyHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: bindings) { _, new in
            AutocompleteSettings.keyBindings = new
            controller.reloadKeyBindings()
        }
        .onChange(of: showKeyHint) { _, new in
            AutocompleteSettings.showKeyHint = new
        }
    }

    private func keyRow(_ title: String, action: AutocompleteAcceptAction) -> some View {
        let combo = Binding<KeyCombo>(
            get: { bindings.combo(for: action) },
            set: { new in
                let result = bindings.assigning(new, to: action)
                bindings = result.bindings
                swapNotice = result.swapped
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(FamilyTheme.font(.subheadline))
            HotkeyRecorderField(combo: combo) { candidate in
                Self.message(for: AutocompleteKeyRules.problem(candidate, reserved: Self.tippiHotkeys()))
            }
        }
    }

    /// Tippis eigene globale Hotkeys, wie gerade gespeichert — auch die
    /// abgeschalteten, damit Einschalten später keinen Konflikt erzeugt —
    /// plus der fest verdrahtete Not-Hotkey ⌃⌥⌘T (AppDelegate).
    static func tippiHotkeys() -> [KeyCombo] {
        [
            KeyComboStore.load(), DictationSettings.combo, TranslateSettings.combo,
            EmojiSettings.combo, NotesSettings.combo, ScreenOCRSettings.combo,
            KeyCombo(keyCode: 17, modifiers: [.control, .option, .command]),
        ]
    }

    static func message(for problem: AutocompleteKeyRules.Problem?) -> String? {
        switch problem {
        case nil:              return nil
        case .escape:          return String(localized: "settings.autocomplete.keys.problem.escape")
        case .typesText:       return String(localized: "settings.autocomplete.keys.problem.typesText")
        case .alreadyShortcut: return String(localized: "settings.autocomplete.keys.problem.alreadyShortcut")
        }
    }
}
