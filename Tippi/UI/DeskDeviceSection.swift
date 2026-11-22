import SwiftUI

/// Settings → General → Desk device (Tippi-Firmware 0.9): switch (off by default), address, key, test.
struct DeskDeviceSection: View {
    @AppStorage(DeskDeviceSettings.enabledKey) private var enabled = false
    @AppStorage(DeskDeviceSettings.hostKey) private var host = DeskDeviceSettings.defaultHost
    @ObservedObject var link: DeskDeviceLink
    let dictation: DictationController
    @State private var key = ""
    @State private var feedback: String?

    var body: some View {
        Section {
            Toggle(String(localized: "settings.deskDevice.toggle"), isOn: $enabled)
                .onChange(of: enabled) { _, _ in link.apply(dictation: dictation) }
            Text(String(localized: "settings.deskDevice.hint"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
            if enabled {
                TextField(String(localized: "settings.deskDevice.host"), text: $host)
                SecureField(String(localized: "settings.deskDevice.key"), text: $key)
                HStack {
                    Button(String(localized: "settings.deskDevice.save")) { save() }
                    Button(String(localized: "settings.deskDevice.test")) { link.test() }
                    Spacer()
                    if let text = feedback ?? link.status {
                        Text(text)
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func save() {
        guard DeskDeviceSettings.validHost(host) != nil else {
            feedback = String(localized: "settings.deskDevice.badHost"); return
        }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !k.isEmpty {
            guard DeskDeviceSettings.validKey(k), DeskDeviceKeychain.save(k) else {
                feedback = String(localized: "settings.deskDevice.badKey"); return
            }
        }
        key = ""
        feedback = nil
        link.test()
    }
}
