import AppKit
import AVFoundation
import SwiftUI

/// Alle Berechtigungen auf einen Blick, je mit „Erteilen“ (Michael, 2026-09-28).
///
/// Vorher verteilt: Bedienungshilfen und Eingabeüberwachung erschienen als
/// Warnung im Hotkeys-Bereich, das Mikrofon unter Diktat, Bildschirmaufnahme und
/// Mitteilungen gar nicht — eine fehlende Bildschirmaufnahme fiel erst beim
/// Auslösen des Bildschirmausschnitts auf.
///
/// Oberste Ebene ist eine ScrollView: Alle Einstellungsbereiche liegen gleichzeitig
/// im ZStack; ein Bereich, der nicht scrollt, kann mit seiner Höhe das ganze Fenster
/// aufblähen (2.17.0: Einstellungsfenster leer, siehe PromptsSettingsTab).
struct PermissionsTab: View {
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "settings.permissions.intro"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "settings.permissions.recheck")) { permissions.refresh() }
                        .controlSize(.small)
                }
                row(symbol: "hand.raised", title: "settings.permissions.accessibility",
                    purpose: "settings.permissions.accessibility.purpose",
                    granted: permissions.accessibilityGranted,
                    grant: {
                        permissions.requestAccessibilityPrompt()
                        permissions.openAccessibilitySettings()
                        bringSystemSettingsToFront()
                    })
                row(symbol: "keyboard", title: "settings.permissions.inputMonitoring",
                    purpose: "settings.permissions.inputMonitoring.purpose",
                    granted: permissions.inputMonitoringGranted,
                    grant: {
                        permissions.requestInputMonitoringPrompt()
                        if !permissions.inputMonitoringGranted {
                            permissions.openInputMonitoringSettings()
                            bringSystemSettingsToFront()
                        }
                    })
                row(symbol: "mic", title: "settings.permissions.microphone",
                    purpose: "settings.permissions.microphone.purpose",
                    granted: permissions.microphoneGranted,
                    grant: {
                        // Nur beim allerersten Mal zeigt macOS den Dialog; danach hilft
                        // nur der Weg über die Systemeinstellungen.
                        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                            permissions.requestMicrophonePermission()
                        } else {
                            permissions.openMicrophoneSettings()
                            bringSystemSettingsToFront()
                        }
                    })
                row(symbol: "rectangle.dashed", title: "settings.permissions.screenRecording",
                    purpose: "settings.permissions.screenRecording.purpose",
                    granted: permissions.screenRecordingGranted,
                    grant: {
                        permissions.requestScreenRecording()
                        bringSystemSettingsToFront()
                    })
                row(symbol: "bell", title: "settings.permissions.notifications",
                    purpose: "settings.permissions.notifications.purpose",
                    granted: permissions.notificationsAllowed == true,
                    grant: {
                        permissions.requestNotifications()
                        if permissions.notificationsAllowed != nil { bringSystemSettingsToFront() }
                    })
                Text(String(localized: "settings.permissions.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { permissions.refresh() }
    }

    private func row(symbol: String, title: String.LocalizationValue, purpose: String.LocalizationValue,
                     granted: Bool, grant: @escaping () -> Void) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: title)).font(.headline)
                    Text(String(localized: purpose))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Label(String(localized: granted ? "settings.permissions.granted" : "settings.permissions.missing"),
                          systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(granted ? Color.green : Color.orange)
                    if !granted {
                        Button(String(localized: "settings.permissions.grant.button"), action: grant)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
            .padding(6)
            .accessibilityElement(children: .combine)
        }
    }

    /// Die Systemeinstellungen öffnen HINTER Tippi (und bewegen sich gar nicht, wenn
    /// sie schon offen sind) — das wirkt wie ein kaputter Knopf. Wie im Hotkeys-Bereich.
    private func bringSystemSettingsToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.systempreferences" }?
                .activate(options: [.activateAllWindows])
        }
    }
}
