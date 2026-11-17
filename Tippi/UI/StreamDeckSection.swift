import SwiftUI

/// Settings → General → Stream Deck (docs/SECURE-DESIGN-stream-deck.md D1/D6): the switch (off by default, off = no
/// socket), connection state and „Install Plugin“, which hands the package to Stream Deck.
struct StreamDeckSection: View {
    @AppStorage(StreamDeckSettings.enabledKey) private var enabled = false
    @ObservedObject var link: StreamDeckLink
    @State private var installError: String?

    var body: some View {
        Section {
            Toggle(String(localized: "settings.streamDeck.toggle"), isOn: $enabled)
                .onChange(of: enabled) { _, _ in link.apply() }
            Text(String(localized: "settings.streamDeck.hint"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
            if enabled {
                HStack {
                    Button(String(localized: "settings.streamDeck.install")) { install() }
                    Spacer()
                    Text(link.connected ? String(localized: "settings.streamDeck.connected")
                                        : String(localized: "settings.streamDeck.waiting"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(link.connected ? Color.green : Color.secondary)
                }
                if link.outdatedPlugin != nil {
                    Text(String(localized: "settings.streamDeck.outdated"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.orange)
                }
                if let installError {
                    Text(installError)
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func install() {
        switch StreamDeckLink.installPlugin() {
        case .success: installError = nil
        case .failure(.missing): installError = String(localized: "settings.streamDeck.error.missing")
        case .failure(.unsigned): installError = String(localized: "settings.streamDeck.error.unsigned")
        case .failure(.pack): installError = String(localized: "settings.streamDeck.error.pack")
        }
    }
}
