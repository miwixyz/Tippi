import SwiftUI

/// „Antwort per Sprache" (Labs, ab Werk aus) in den Diktat-Einstellungen:
/// Schalter, eigene Taste (ab Werk ⌃⌥⌘A), Vorwort mit Varianten, Name für den Gruß.
struct ReplySettingsSection: View {
    @State private var enabled = ReplySettings.isEnabled
    @State private var hotkeyEnabled = ReplySettings.hotkeyEnabled
    @State private var combo = ReplySettings.combo
    @State private var prefix = ReplySettings.prefix
    @State private var variants = ReplySettings.prefixVariants.joined(separator: ", ")
    @State private var name = ReplySettings.signOffName
    @ObservedObject private var manager: HotkeyManager

    init() {
        _manager = ObservedObject(wrappedValue: AppDelegate.shared?.replyHotkeyManager ?? HotkeyManager(id: 910))
    }

    private var conflict: String? {
        MailDictationSettings.conflict(of: combo, in: ReplySettings.takenCombos())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle(String(localized: "settings.reply.enable"), isOn: $enabled)
                    .onChange(of: enabled) { _, new in
                        ReplySettings.isEnabled = new
                        AppDelegate.shared?.restartReplyHotkey()
                    }
                Text("Labs")
                    .font(FamilyTheme.font(.caption2, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
            }
            Text(String(localized: "settings.reply.body"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !MLXServerManager.isInstalled {
                Label(String(localized: "settings.reply.needsMLX"), systemImage: "exclamationmark.triangle.fill")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.orange)
            }
            if enabled {
                Toggle(String(localized: "settings.reply.hotkey"), isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { _, new in
                        ReplySettings.hotkeyEnabled = new
                        AppDelegate.shared?.restartReplyHotkey()
                    }
                if hotkeyEnabled {
                    HotkeyRecorderField(combo: $combo)
                        .onChange(of: combo) { _, new in
                            ReplySettings.combo = new
                            AppDelegate.shared?.restartReplyHotkey()
                        }
                    status
                }
                LabeledContent(String(localized: "settings.reply.prefix")) {
                    TextField(ReplySettings.defaultPrefix, text: $prefix)
                        .onChange(of: prefix) { _, new in ReplySettings.prefix = new }
                }
                LabeledContent(String(localized: "settings.reply.variants")) {
                    TextField(String(localized: "settings.reply.variants.placeholder"), text: $variants)
                        .onChange(of: variants) { _, new in
                            ReplySettings.prefixVariants = new.split(separator: ",").map(String.init)
                        }
                }
                LabeledContent(String(localized: "settings.reply.name")) {
                    TextField(String(localized: "settings.reply.name.placeholder"), text: $name)
                        .onChange(of: name) { _, new in ReplySettings.signOffName = new }
                }
                Text(String(localized: "settings.reply.prefix.body"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
