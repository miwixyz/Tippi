import AppKit
import Foundation

/// A user-chosen keyboard combination (modifiers + key).
/// Persisted to UserDefaults via Codable.
struct KeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRaw: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRaw)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        // Keep only the four real modifier keys — strip caps lock, function, numeric-pad bits.
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        self.modifiersRaw = modifiers.intersection(relevant).rawValue
    }

    /// Default: ⌥⌘T (Option + Command + T). Easy two-hand combo, rarely conflicts.
    static let `default` = KeyCombo(keyCode: 17, modifiers: [.option, .command])

    /// Dictation default: ⌃⌥⌘M (Control + Option + Command + M — M for microphone).
    /// A distinct key from the main trigger; ⌥⌘D is a reserved system shortcut
    /// (Dock auto-hide) and ⌃⌥⌘D collides with the common ⌃⌥⇧⌘D main combo.
    static let dictationDefault = KeyCombo(keyCode: 46, modifiers: [.control, .option, .command])

    var displayString: String {
        var parts: [String] = []
        let m = modifiers
        if m.contains(.control)  { parts.append("⌃") }
        if m.contains(.option)   { parts.append("⌥") }
        if m.contains(.shift)    { parts.append("⇧") }
        if m.contains(.command)  { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for code: UInt16) -> String {
        switch code {
        case 0:  return "A"
        case 1:  return "S"
        case 2:  return "D"
        case 3:  return "F"
        case 4:  return "H"
        case 5:  return "G"
        case 6:  return "Z"
        case 7:  return "X"
        case 8:  return "C"
        case 9:  return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        default:  return "Key#\(code)"
        }
    }
}

@MainActor
enum KeyComboStore {
    private static let key = "tippi.hotkeyCombo.v1"

    static func load() -> KeyCombo {
        guard let data = UserDefaults.standard.data(forKey: key),
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
            return .default
        }
        return combo
    }

    static func save(_ combo: KeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
