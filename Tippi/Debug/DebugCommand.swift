#if DEBUG
import Foundation

/// Ein Befehl an die Bild-Testkopie (docs/SECURE-DESIGN-befehlskanal.md B6). Feste Liste, alles andere ist ungültig.
struct DebugCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Version, Kennung, Freigaben, offene erlaubte Fenster – nur Zahlen und Kennungen.
        case status
        /// Bild eines eigenen Fensters (nur Allgemein, Hilfe, Über – nie Anbieter, Snippets, Verlauf …).
        case snapshot(window: String)
        /// Hell, dunkel oder wie das System.
        case appearance(String)
    }

    let id: String
    let kind: Kind

    static let settingsWindow = "einstellungen"
    static let helpWindow = "hilfe"
    static let aboutWindow = "ueber"
    /// Fenster, von denen ein Bild erlaubt ist (B5). Anbieter, Prompts, Snippets, Verlauf, Diktat,
    /// Autovervollständigung, Notizen zeigen im echten Tippi echte Inhalte und fehlen bewusst.
    static let snapshotWindows: Set<String> = [settingsWindow, helpWindow, aboutWindow]
    static let appearances: Set<String> = ["light", "dark", "system"]

    /// Größte Nachricht (4 Byte Länge + JSON). Größer → Verbindung zu.
    static let maxFrame = 4096

    /// Nur das Developer-ID-signierte Steuerprogramm `tippictl` (Team LTKJ6Z2VYB) darf Befehle schicken.
    /// Nicht nur `anchor apple generic`: Apple-Development-Builds tragen `get-task-allow`.
    static let ctlRequirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.tippi.ctl" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    /// `{"v":1,"id":"…","cmd":"status"|"snapshot"|"appearance", …}`; `id` 1–32 Zeichen a–z, A–Z, 0–9 (wird Dateiname).
    static func parse(_ payload: Data) -> DebugCommand? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let version = obj["v"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let id = obj["id"] as? String, (1...32).contains(id.count),
              id.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }),
              let cmd = obj["cmd"] as? String else { return nil }
        switch cmd {
        case "status":
            return DebugCommand(id: id, kind: .status)
        case "snapshot":
            guard let window = obj["window"] as? String, snapshotWindows.contains(window) else { return nil }
            return DebugCommand(id: id, kind: .snapshot(window: window))
        case "appearance":
            guard let mode = obj["mode"] as? String, appearances.contains(mode) else { return nil }
            return DebugCommand(id: id, kind: .appearance(mode))
        default:
            return nil
        }
    }

    enum Frame: Equatable {
        case message(Data), needMore, invalid
    }

    /// Nimmt die nächste vollständige Nachricht vorne aus `buffer`. `invalid`: Länge 0 oder größer als `maxFrame` –
    /// der Server trennt dann die Verbindung.
    static func nextFrame(_ buffer: inout Data) -> Frame {
        guard buffer.count >= 4 else { return .needMore }
        let head = [UInt8](buffer.prefix(4))
        let length = Int(head[0]) << 24 | Int(head[1]) << 16 | Int(head[2]) << 8 | Int(head[3])
        guard length > 0, length + 4 <= maxFrame else { return .invalid }
        guard buffer.count >= length + 4 else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(payload)
    }

    static func frame(_ object: [String: Any]) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object), json.count + 4 <= maxFrame else { return nil }
        return withUnsafeBytes(of: UInt32(json.count).bigEndian) { Data($0) } + json
    }
}
#endif
