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
                    .font(FamilyTheme.font(.headline))
            }
            .onChange(of: dictationEnabled) { _, new in
                DictationSettings.isEnabled = new
                AppDelegate.shared?.restartDictationHotkey()
            }

            Text(String(localized: "settings.voice.dictation.body"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if dictationEnabled {
                if SpeechEngine.current == .whisper && !WhisperConfig.isConfigured {
                    Label(String(localized: "settings.voice.dictation.needsModel"),
                          systemImage: "exclamationmark.circle")
                        .font(FamilyTheme.font(.caption))
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

                Divider().padding(.vertical, 4)
                MailDictationHotkeyControls()
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
            .font(FamilyTheme.font(.caption))
            .foregroundStyle(.secondary)

        // This style listens via a CGEventTap, unlike the key
        // combination (Carbon), which needs no permission. Without
        // this notice the hot key would simply do nothing and the
        // failure would only be visible in the system log.
        if !inputMonitoringGranted {
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "settings.voice.dictation.mode.needsPermission"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(FamilyTheme.font(.caption, weight: .medium))
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

/// „Diktat für Mails": eigener Hotkey (ab Werk ⌃⌥⌘B), Layout immer an. Zeigt, ob der
/// Hotkey wirklich registriert ist, und nennt ein schon belegtes Kürzel beim Namen.
private struct MailDictationHotkeyControls: View {
    @State private var enabled = MailDictationSettings.isEnabled
    @State private var combo = MailDictationSettings.combo
    @ObservedObject private var manager: HotkeyManager

    init() {
        _manager = ObservedObject(wrappedValue: AppDelegate.shared?.mailDictationHotkeyManager ?? HotkeyManager(id: 907))
    }

    private var conflict: String? {
        MailDictationSettings.conflict(of: combo, in: MailDictationSettings.takenCombos())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(String(localized: "settings.voice.dictation.mail.enable"), isOn: $enabled)
                .onChange(of: enabled) { _, new in
                    MailDictationSettings.isEnabled = new
                    AppDelegate.shared?.restartMailDictationHotkey()
                }
            Text(String(localized: "settings.voice.dictation.mail.body"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                HotkeyRecorderField(combo: $combo)
                    .onChange(of: combo) { _, new in
                        MailDictationSettings.combo = new
                        AppDelegate.shared?.restartMailDictationHotkey()
                    }
                status
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let conflict {
            Label(String(format: String(localized: "settings.voice.dictation.mail.conflict"), conflict),
                  systemImage: "exclamationmark.triangle.fill")
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.orange)
        } else if let error = manager.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.orange)
        } else if manager.isActive {
            Label(String(format: String(localized: "settings.hotkeys.active"), combo.displayString),
                  systemImage: "checkmark.circle.fill")
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.green)
        } else {
            Label(String(localized: "settings.hotkeys.inactive.combo"), systemImage: "pause.circle")
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
        }
    }
}
