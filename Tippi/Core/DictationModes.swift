import CoreGraphics
import Foundation

// MARK: - Diktat-Modi
//
// Idee nach Blitztext (MIT, siehe NOTICES.md): ein Kürzel startet das Diktat direkt
// in einem Modus, nach dem Sprechen läuft der Prompt des Modus auf das Transkript,
// eingefügt wird das Ergebnis. Bei Tippi ist das Kürzel die Tap-or-Hold-Taste des
// Diktats plus eine Zusatztaste (⇧ ⌃ ⌘ fn), gehalten beim Start der Aufnahme.
//
// Wann die Zusatztaste zählt (entschieden 2026-10-27):
// - Halten: im Moment, in dem die Aufnahme beginnt (Haltegrenze 400 ms nach dem
//   Drücken). ⇧ darf also kurz vor oder kurz nach der Diktat-Taste kommen; wer sie
//   erst während der laufenden Aufnahme drückt, ändert nichts mehr.
// - Doppeltippen: im Moment, in dem das zweite Antippen losgelassen wird.
// Ein zufälliges ⇧ beim Tippen kann keinen Modus auslösen: Sobald zwischen Drücken
// und Loslassen der Diktat-Taste eine normale Taste fällt, verwirft `HotkeyManager`
// die ganze Geste (`otherKeyWhileHeld`). Eine gehaltene Zusatz-*Modifiertaste*
// erzeugt dagegen kein keyDown, bricht also nichts ab.

/// Die vier Plätze. Links/rechts ist egal.
enum DictationModeSlot: String, CaseIterable, Identifiable {
    case shift, control, command, fn
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shift: return String(localized: "dictation.modes.slot.shift")
        case .control: return String(localized: "dictation.modes.slot.control")
        case .command: return String(localized: "dictation.modes.slot.command")
        case .fn: return "fn"
        }
    }

    /// IOKit-Gerätebits (`NX_DEVICE*`) für links und rechts, wie in
    /// `HotkeyManager.isModifierPressed`. fn hat keine.
    fileprivate var deviceBits: UInt64 {
        switch self {
        case .shift: return 0x0002 | 0x0004
        case .control: return 0x0001 | 0x2000
        case .command: return 0x0008 | 0x0010
        case .fn: return 0
        }
    }

    fileprivate var genericFlag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .command: return .maskCommand
        case .fn: return .maskSecondaryFn
        }
    }
}

/// Was ein Platz tut.
enum DictationModeAssignment: Hashable {
    case empty
    /// Der Diktat-Bereinigungs-Prompt (`DictationSettings.effectivePostProcessPrompt`).
    case improve
    /// Ein mitgelieferter oder eigener Prompt, `DemoPrompt.id`.
    case prompt(id: String)

    var storageToken: String {
        switch self {
        case .empty: return "empty"
        case .improve: return "improve"
        case .prompt(let id): return "prompt:" + id
        }
    }

    init?(storageToken token: String) {
        switch token {
        case "empty": self = .empty
        case "improve": self = .improve
        default:
            guard token.hasPrefix("prompt:"), token.count > 7 else { return nil }
            self = .prompt(id: String(token.dropFirst(7)))
        }
    }
}

/// Ein aufgelöster Modus, festgehalten beim Start der Aufnahme.
struct DictationMode: Equatable {
    enum Action: Equatable {
        case improve
        case prompt(DemoPrompt)
    }
    let slot: DictationModeSlot
    let title: String
    let symbol: String
    let action: Action
}

extension DictationSource {
    var dictationMode: DictationMode? {
        if case .mode(let mode) = self { return mode }
        return nil
    }
}

@MainActor
enum DictationModes {
    /// Dieselbe Ablage wie alle Diktat-Einstellungen; Tests tauschen sie dort aus.
    private static var store: UserDefaults { DictationSettings.store }
    static let enabledKey = "dictation.modes.enabled.v1"
    static let assignmentsKey = "dictation.modes.assignments.v1"
    nonisolated static let storageVersion = 1

    /// Hauptschalter, ab Werk an.
    static var isEnabled: Bool {
        get { store.object(forKey: enabledKey) as? Bool ?? true }
        set { store.set(newValue, forKey: enabledKey) }
    }

    nonisolated static let defaultAssignments: [DictationModeSlot: DictationModeAssignment] = [
        .shift: .improve,
        .control: .prompt(id: "defuse"),
        .command: .prompt(id: "addEmojis"),
        .fn: .empty,
    ]

    static func assignment(for slot: DictationModeSlot) -> DictationModeAssignment {
        decode(store.data(forKey: assignmentsKey))[slot] ?? .empty
    }

    static func setAssignment(_ assignment: DictationModeAssignment, for slot: DictationModeSlot) {
        var all = decode(store.data(forKey: assignmentsKey))
        all[slot] = assignment
        if let data = encode(all) { store.set(data, forKey: assignmentsKey) }
    }

    // MARK: Speichern (rein)

    private struct Stored: Codable {
        let version: Int
        let slots: [String: String]
    }

    /// Fehlt etwas, gilt pro Platz die Werksbelegung; eine unbekannte Version oder
    /// kaputte Daten ergeben die Werksbelegung insgesamt, ohne Absturz.
    nonisolated static func decode(_ data: Data?) -> [DictationModeSlot: DictationModeAssignment] {
        var result = defaultAssignments
        guard let data else { return result }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == storageVersion else {
            NSLog("Tippi: dictation modes — unreadable or unknown version, using defaults")
            return result
        }
        for slot in DictationModeSlot.allCases {
            if let token = stored.slots[slot.rawValue], let assignment = DictationModeAssignment(storageToken: token) {
                result[slot] = assignment
            }
        }
        return result
    }

    nonisolated static func encode(_ assignments: [DictationModeSlot: DictationModeAssignment]) -> Data? {
        let slots = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value.storageToken) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(Stored(version: storageVersion, slots: slots))
    }

    // MARK: Erkennung (rein)

    /// Welche Zusatztaste neben der Diktat-Taste `trigger` gehalten wird. Genau eine
    /// zählt; mehrere gleichzeitig sind mehrdeutig und ergeben das normale Diktat,
    /// statt zu raten. Die Feststelltaste (`maskAlphaShift`) zählt nie.
    nonisolated static func slot(in flags: CGEventFlags, trigger: ModifierKey) -> DictationModeSlot? {
        let raw = flags.rawValue
        let hasDeviceBits = raw & 0x207F != 0
        let triggerBit = deviceBit(of: trigger)
        let held = DictationModeSlot.allCases.filter { slot in
            if slot.deviceBits == 0 || !hasDeviceBits {
                // Ohne Gerätebits ist die eigene Gruppe der Diktat-Taste nicht von der
                // Zusatztaste zu unterscheiden (rechtes ⇧ als Diktat-Taste setzt `maskShift`).
                return flags.contains(slot.genericFlag) && genericFlag(of: trigger) != slot.genericFlag
            }
            return raw & (slot.deviceBits & ~triggerBit) != 0
        }
        return held.count == 1 ? held[0] : nil
    }

    private nonisolated static func deviceBit(of key: ModifierKey) -> UInt64 {
        switch key {
        case .leftControl: return 0x0001
        case .leftShift: return 0x0002
        case .rightShift: return 0x0004
        case .leftCommand: return 0x0008
        case .rightCommand: return 0x0010
        case .leftOption: return 0x0020
        case .rightOption: return 0x0040
        case .rightControl: return 0x2000
        }
    }

    private nonisolated static func genericFlag(of key: ModifierKey) -> CGEventFlags {
        switch key {
        case .leftShift, .rightShift: return .maskShift
        case .leftControl, .rightControl: return .maskControl
        case .leftOption, .rightOption: return .maskAlternate
        case .leftCommand, .rightCommand: return .maskCommand
        }
    }

    // MARK: Auflösung

    /// Platz → Modus. `nil` = normales Diktat: leerer Platz, oder der belegte Prompt
    /// existiert nicht mehr (gelöscht, auf diesem Mac noch nicht per iCloud da). Die
    /// Belegung bleibt dabei gespeichert, damit ein später ankommender Prompt wieder greift.
    static func resolve(_ assignment: DictationModeAssignment, slot: DictationModeSlot,
                        lookup: (String) -> DemoPrompt?) -> DictationMode? {
        switch assignment {
        case .empty:
            return nil
        case .improve:
            return DictationMode(slot: slot, title: String(localized: "dictation.modes.improve"),
                                 symbol: "wand.and.stars", action: .improve)
        case .prompt(let id):
            guard let prompt = lookup(id) else { return nil }
            return DictationMode(slot: slot, title: prompt.title, symbol: prompt.symbol, action: .prompt(prompt))
        }
    }

    /// Einstieg für `AppDelegate`: die Flags beim Start der Geste → Quelle des Diktats.
    /// Modi gibt es nur mit Tap-or-Hold und eingeschaltetem Hauptschalter.
    static func source(for flags: CGEventFlags) -> DictationSource {
        guard isEnabled, DictationSettings.mode == .tapOrHold,
              let slot = slot(in: flags, trigger: DictationSettings.tapOrHoldModifier),
              let mode = resolve(assignment(for: slot), slot: slot, lookup: DemoPrompt.resolve(id:)) else {
            return .standard
        }
        return .mode(mode)
    }
}
