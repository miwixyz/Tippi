import Foundation

/// Bild-Testkopie (docs/SECURE-DESIGN-befehlskanal.md): Debug-Build mit eigener Kennung, damit ihre
/// Bildschirmaufnahme-Freigabe nicht auch für das echte Tippi gilt. Sie startet nur Fenster + Befehlskanal –
/// keine Hotkeys, keine Event-Taps, kein Diktat, kein Sparkle, keine Verbindung zu Gnotchi (B3).
///
/// Im Release-Build gibt es den Zweig nicht: `isActive` ist dort immer `false`, Kennung und Ersatzordner stehen
/// nicht im Binary.
enum BildKopie {
    static var isActive: Bool {
        #if DEBUG
        return Bundle.main.bundleIdentifier == "dev.mwlr.tippi.bild"
        #else
        return false
        #endif
    }

    /// `~/Library/Application Support` – in der Kopie ein eigener, leerer Ersatz (B4). Jeder fest „Tippi“
    /// heißende Ort (Snippets, Espanso-Ordner, Verlauf, Notizen, Kurse, Modelle, Gnotchi-Socket) geht hierüber.
    static var applicationSupport: URL {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if isActive { return real.appendingPathComponent("Tippi Bild/Daten", isDirectory: true) }
        #endif
        return real
    }

    /// Schlüsselbund-Dienst: in der Kopie ein eigener Name – sie sieht nie einen Eintrag des echten Tippi
    /// (API-Schlüssel, Verlaufsschlüssel, Snippet-Freigaben) und löst nie einen Schlüsselbund-Dialog aus (B4).
    static func keychainService(_ service: String) -> String {
        #if DEBUG
        if isActive { return "dev.mwlr.tippi.bild." + service }
        #endif
        return service
    }
}
