import Foundation

/// Einstellungen der Labs-Funktion „Autovervollständigung beim Tippen".
///
/// Sicherheitsdesign: `docs/SECURE-DESIGN-autocomplete.md`. Gespeichert wird nur
/// an/aus und die Ausschlussliste — nie etwas vom Getippten (§1 Klassifikation).
///
/// Schlüssel beginnen mit `tippi.`, damit `scripts/real-defaults-guard.sh` sie
/// ohne Änderung mitprüft.
@MainActor
enum AutocompleteSettings {
    /// See `DictationSettings.store`: `.standard` in the app, a throwaway suite in
    /// tests — the test host shares the installed app's preferences file.
    static var store: UserDefaults = .standard
    private static let enabledKey = "tippi.autocomplete.enabled.v1"
    private static let excludedKey = "tippi.autocomplete.excludedBundleIDs.v1"

    /// **Ab Werk AUS** (Design §8): Die Funktion liest alles, was im fokussierten
    /// Feld vor dem Cursor steht, und braucht einen aktiven Tastatur-Tap.
    static var isEnabled: Bool {
        get { store.object(forKey: enabledKey) as? Bool ?? false }
        set { store.set(newValue, forKey: enabledKey) }
    }

    /// Ausschlussliste ab Werk (Design §3): Passwortmanager und Terminals — dort
    /// landen Geheimnisse. Bundle-IDs 2026-09-25 an den installierten Apps
    /// gemessen, soweit vorhanden (Passwörter, Schlüsselbund, Terminal, 1Password 8).
    static let defaultExcludedBundleIDs: [String] = [
        "com.1password.1password",      // 1Password 8
        "com.agilebits.onepassword7",   // 1Password 7
        "com.bitwarden.desktop",        // Bitwarden
        "com.apple.keychainaccess",     // Schlüsselbundverwaltung
        "com.apple.Passwords",          // Passwörter-App (macOS 15+)
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]

    /// Fehlt der Schlüssel, gilt die Liste ab Werk. Eine vom Nutzer geleerte
    /// Liste bleibt leer — das ist eine bewusste Entscheidung, kein Defekt.
    static var excludedBundleIDs: [String] {
        get { store.stringArray(forKey: excludedKey) ?? defaultExcludedBundleIDs }
        set { store.set(normalized(newValue), forKey: excludedKey) }
    }

    static func addExclusion(_ bundleID: String) {
        excludedBundleIDs += [bundleID]
    }

    static func removeExclusion(_ bundleID: String) {
        excludedBundleIDs = excludedBundleIDs.filter { $0 != bundleID }
    }

    /// Leerzeichen weg, Leeres und Doppeltes raus, Reihenfolge bleibt.
    nonisolated static func normalized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
