import AppKit
import SwiftUI

/// Einstellungen → Hotkeys: der Diktat-Hotkey — ein/aus, Art (Kombination oder
/// einzelne Sondertaste), die Taste selbst und der Hinweis auf die
/// Eingabeüberwachung. Bis 2026-09-28 stand das im Bereich „Sprache" (heute
/// „Diktat"); Einstellungen und Verhalten sind unverändert, nur der Ort ist neu.
/// Was das Diktat danach tut (Anzeige, Enter, KI-Glättung), bleibt dort.
struct DictationHotkeySection: View {
    @State private var dictationEnabled: Bool = DictationSettings.isEnabled
    @State private var dictationCombo: KeyCombo = DictationSettings.combo
    @State private var dictationMode: DictationSettings.InputMode = DictationSettings.mode
    @State private var dictationTapOrHoldModifier: ModifierKey = DictationSettings.tapOrHoldModifier
    @State private var inputMonitoringGranted: Bool = HotkeyManager.hasInputMonitoringPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $dictationEnabled) {
                Text(String(localized: "settings.voice.dictation.enable"))
                    .font(.headline)
            }
            .onChange(of: dictationEnabled) { _, new in
                DictationSettings.isEnabled = new
                AppDelegate.shared?.restartDictationHotkey()
            }

            Text(String(localized: "settings.voice.dictation.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if dictationEnabled {
                if SpeechEngine.current == .whisper && !WhisperConfig.isConfigured {
                    Label(String(localized: "settings.voice.dictation.needsModel"),
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker(String(localized: "settings.voice.dictation.mode.label"),
                       selection: $dictationMode) {
                    Text(String(localized: "settings.voice.dictation.mode.combo"))
                        .tag(DictationSettings.InputMode.combo)
                    Text(String(localized: "settings.voice.dictation.mode.tapOrHold"))
                        .tag(DictationSettings.InputMode.tapOrHold)
                }
                .pickerStyle(.segmented)
                .onChange(of: dictationMode) { _, new in
                    DictationSettings.mode = new
                    inputMonitoringGranted = HotkeyManager.hasInputMonitoringPermission
                    AppDelegate.shared?.restartDictationHotkey()
                }

                if dictationMode == .combo {
                    HotkeyRecorderField(combo: $dictationCombo)
                        .onChange(of: dictationCombo) { _, new in
                            DictationSettings.combo = new
                            AppDelegate.shared?.restartDictationHotkey()
                        }
                } else {
                    tapOrHoldControls
                }
            }
        }
    }

    @ViewBuilder
    private var tapOrHoldControls: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "settings.voice.dictation.mode.modifier"))
            ModifierRecorderField(modifier: $dictationTapOrHoldModifier)
        }
        .onChange(of: dictationTapOrHoldModifier) { _, new in
            DictationSettings.tapOrHoldModifier = new
            AppDelegate.shared?.restartDictationHotkey()
        }

        Text(String(localized: "settings.voice.dictation.mode.tapOrHold.body"))
            .font(.caption)
            .foregroundStyle(.secondary)

        // This style listens via a CGEventTap, unlike the key
        // combination (Carbon), which needs no permission. Without
        // this notice the hot key would simply do nothing and the
        // failure would only be visible in the system log.
        if !inputMonitoringGranted {
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "settings.voice.dictation.mode.needsPermission"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Button(String(localized: "settings.voice.dictation.mode.grantPermission")) {
                        HotkeyManager.requestInputMonitoringPermission()
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                    Button(String(localized: "settings.voice.dictation.mode.recheckPermission")) {
                        inputMonitoringGranted = HotkeyManager.hasInputMonitoringPermission
                        AppDelegate.shared?.restartDictationHotkey()
                    }
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
