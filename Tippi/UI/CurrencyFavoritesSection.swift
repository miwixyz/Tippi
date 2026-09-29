import SwiftUI

/// Settings → General: which currencies the selection bar and the hotkey
/// popup offer as conversion targets. Carries the attribution the rate
/// provider requires ("Rates By Exchange Rate API" with a link).
struct CurrencyFavoritesSection: View {
    @State private var favorites = CurrencySettings.favorites

    private static let attributionURL = URL(string: "https://www.exchangerate-api.com")

    var body: some View {
        Section(String(localized: "currency.settings.title")) {
            Text(String(localized: "currency.settings.favorites"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
            // Spelled out, because a highlighted chip alone did not read as
            // "selected": clicking CRC to add it removed it (2026-09-28).
            Text(String(format: String(localized: "currency.settings.selected"),
                        favorites.isEmpty ? "—" : favorites.joined(separator: " · ")))
                .font(FamilyTheme.font(.callout, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(CurrencyCatalog.codes, id: \.self) { code in
                    chip(code)
                }
            }
            if let url = Self.attributionURL {
                Link(String(localized: "currency.settings.attribution"), destination: url)
                    .font(FamilyTheme.font(.caption))
            }
        }
    }

    private func chip(_ code: String) -> some View {
        let isOn = favorites.contains(code)
        return Button {
            toggle(code)
        } label: {
            Text(verbatim: isOn ? "✓ \(code)" : code)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 22)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help(isOn ? String(localized: "currency.settings.remove") : String(localized: "currency.settings.add"))
        .disabled(!isOn && favorites.count >= CurrencySettings.maxFavorites)
    }

    private func toggle(_ code: String) {
        if let index = favorites.firstIndex(of: code) {
            favorites.remove(at: index)
        } else if favorites.count < CurrencySettings.maxFavorites {
            favorites.append(code)
        }
        CurrencySettings.favorites = favorites
        favorites = CurrencySettings.favorites
    }
}
