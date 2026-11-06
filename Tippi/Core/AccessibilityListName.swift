import Foundation

/// Name der Liste in Systemeinstellungen → Datenschutz & Sicherheit, in der Tippi freigegeben wird.
/// macOS 27 hat sie umbenannt: „Bedienungshilfen“ → „Gerätesteuerung und Datenzugriff“
/// (gemessen in SecurityPrivacyExtension.appex, Schlüssel ACCESSIBILITY). Tippi läuft ab macOS 15,
/// deshalb wird der Name zur Laufzeit gewählt. Der Einstellungsbereich „Bedienungshilfen“
/// (Anzeige, Gesprochene Inhalte) heißt weiter so und ist hier nicht gemeint.
enum AccessibilityListName {
    static func name(majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> String {
        majorVersion >= 27
            ? String(localized: "permissions.accessibilityList.current")
            : String(localized: "permissions.accessibilityList.legacy")
    }

    /// Lokalisierter Text mit dem Listennamen an der Stelle von `%@`.
    static func text(_ key: String.LocalizationValue) -> String {
        String(format: String(localized: key), name())
    }
}
