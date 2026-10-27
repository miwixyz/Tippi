import SwiftUI

/// Einstellungen → Hotkeys → Diktat: die Diktat-Modi (`DictationModes`). Hauptschalter
/// und vier Plätze (⇧ ⌃ ⌘ und die andere ⌥), jeder frei belegbar: leer, Verbessern oder ein Prompt.
/// Nur mit der Diktat-Art „Einzelne Taste" (Tap or Hold) wirksam, sonst ein Hinweis.
struct DictationModesSection: View {
    let inputMode: DictationSettings.InputMode
    let trigger: ModifierKey
    @State private var enabled = DictationModes.isEnabled
    @State private var assignments: [DictationModeSlot: DictationModeAssignment] =
        Dictionary(uniqueKeysWithValues: DictationModeSlot.allCases.map { ($0, DictationModes.assignment(for: $0)) })
    /// Neu gezeichnet, wenn eigene Prompts dazukommen oder verschwinden.
    @ObservedObject private var customPrompts = CustomPromptStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(String(localized: "settings.voice.dictation.modes.enable"), isOn: $enabled)
                .onChange(of: enabled) { _, new in DictationModes.isEnabled = new }
            Text(String(format: String(localized: "settings.voice.dictation.modes.body"), trigger.displayName))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if inputMode != .tapOrHold {
                Label(String(localized: "settings.voice.dictation.modes.needsTapOrHold"),
                      systemImage: "info.circle")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if enabled {
                ForEach(DictationModeSlot.allCases) { slot in
                    Picker("\(trigger.displayName) + \(slot.displayName)", selection: binding(for: slot)) {
                        Text(String(localized: "dictation.modes.empty")).tag(DictationModeAssignment.empty)
                        Text(String(localized: "dictation.modes.improve.picker")).tag(DictationModeAssignment.improve)
                        Divider()
                        ForEach(DemoPrompt.all) { prompt in
                            Text(prompt.title).tag(DictationModeAssignment.prompt(id: prompt.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    /// Ein gelöschter Prompt zeigt sich als „Leer" — genau so verhält sich der Platz.
    private func binding(for slot: DictationModeSlot) -> Binding<DictationModeAssignment> {
        Binding(
            get: {
                let current = assignments[slot] ?? .empty
                if case .prompt(let id) = current, DemoPrompt.resolve(id: id) == nil { return .empty }
                return current
            },
            set: { new in
                assignments[slot] = new
                DictationModes.setAssignment(new, for: slot)
            }
        )
    }
}
