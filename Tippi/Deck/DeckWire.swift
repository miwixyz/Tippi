import Foundation

/// Stream Deck (docs/SECURE-DESIGN-stream-deck.md): message format between Tippi and its plugin „TippiDeck“.
/// The same file is compiled into both targets so sending and checking can never drift apart.
/// Frame: 4-byte big-endian length + JSON object (same shape as Gnotchi's `deck.sock`).
enum DeckWire {

    static let socketName = "deck.sock"
    static let pluginID = "dev.mwlr.tippi.deck"
    /// Plugin folder in Tippi's Resources and the name of the package handed to Stream Deck.
    static let pluginFolder = "dev.mwlr.tippi.deck.sdPlugin"
    /// Executable inside the plugin folder (manifest `CodePath`).
    static let executable = "tippideck"
    /// Largest frame Tippi → plugin: up to 60 prompt titles of ≤ 40 characters (UTF-8 up to 4 bytes) plus state.
    static let maxFrame = 16_384
    /// Largest command (plugin → Tippi). Commands are tiny; anything bigger is not a command.
    static let maxCommandBytes = 512
    static let maxPrompts = 60
    static let maxTitleChars = 40
    static let maxModes = 4
    /// Commands per second Tippi accepts (D5); keys and dials stay far below.
    static let maxPerSecond = 20
    /// Level bar steps (0…maxLevel) while recording.
    static let maxLevel = 20

    /// Elgato's Stream Deck app (measured 2026-11-17 by Gnotchi: `Developer ID Application: Corsair Memory, Inc. (Y93VXCB8Q5)`).
    static let streamDeckRequirement =
        #"anchor apple generic and identifier "com.elgato.StreamDeck" and certificate leaf[subject.OU] = "Y93VXCB8Q5""#

    /// The plugin, as Tippi checks the socket peer (Developer ID, own team).
    static let pluginRequirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.tippi.deck" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    /// Tippi itself, as the plugin checks the listening process before it sends anything.
    static let tippiRequirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "com.tippi.app" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    // MARK: Vocabulary (fixed lists, D3)

    enum DictationStep: String, CaseIterable, Sendable { case toggle, holdStart, holdEnd }

    /// Dictation mode by slot – resolved against Tippi's own assignment, like the extra modifier key.
    enum ModeSlot: String, CaseIterable, Sendable { case standard, shift, control, command, option }

    enum Action: String, CaseIterable, Sendable {
        case mailDictation, voiceNote, popup, translate, emoji, notes, quickNotes, screenText, password, pause, autocomplete, language
    }

    enum Command: Equatable, Sendable {
        case hello(version: String)
        case watch
        case dictation(DictationStep, mode: ModeSlot)
        case run(Action)
        case prompt(id: String)
    }

    enum DictationState: String, Sendable { case idle, recording, transcribing }

    struct Item: Equatable, Sendable {
        let id: String
        let title: String
    }

    /// Everything the plugin may show. Never text, transcripts, results, notes, app names (D4).
    struct Status: Equatable, Sendable {
        var dictation: DictationState = .idle
        /// Dictation switched on and the speech engine is ready.
        var ready = false
        var level = 0
        var paused = false
        var autocomplete = false
        var language = "auto"
        /// The source of the running dictation, so the right key lights up.
        var source: String?
        var prompts: [Item] = []
        /// Modes with an assignment (slot → title).
        var modes: [Item] = []
    }

    // MARK: Checks

    /// Prompt id: letters, digits, `.`, `_`, `-`, 1…64 characters. Custom prompts use UUID strings.
    static func isValidID(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 64 else { return false }
        return s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) }
    }

    static func isValidLanguage(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 8 && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.letters.contains($0) || $0 == "-") }
    }

    /// Control and format characters out, whitespace runs collapsed, cut to `limit`.
    static func clean(_ s: String, limit: Int = maxTitleChars) -> String {
        let scalars = s.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || scalar.properties.generalCategory == .format ? " " : Character(scalar)
        }
        let collapsed = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    private static func isNumberOne(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
        return n.doubleValue == 1
    }

    // MARK: Commands (plugin → Tippi)

    /// One command message. Anything unknown, mistyped or oversized → nil (Tippi closes the connection).
    static func parse(_ payload: Data) -> Command? {
        guard payload.count <= maxCommandBytes,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              isNumberOne(obj["v"]) else { return nil }
        if let version = obj["hello"] as? String {
            return version.count <= 32 ? .hello(version: version) : nil
        }
        if obj["watch"] as? Bool == true { return .watch }
        switch obj["cmd"] as? String {
        case "dictation":
            guard let step = (obj["do"] as? String).flatMap(DictationStep.init(rawValue:)) else { return nil }
            let mode = obj["mode"] == nil ? .standard : (obj["mode"] as? String).flatMap(ModeSlot.init(rawValue:))
            guard let mode else { return nil }
            return .dictation(step, mode: mode)
        case "run":
            return (obj["action"] as? String).flatMap(Action.init(rawValue:)).map(Command.run)
        case "prompt":
            guard let id = obj["id"] as? String, isValidID(id) else { return nil }
            return .prompt(id: id)
        default:
            return nil
        }
    }

    static func encode(_ c: Command) -> [String: Any] {
        switch c {
        case .hello(let version): ["v": 1, "hello": version]
        case .watch: ["v": 1, "watch": true]
        case .dictation(let step, let mode): ["v": 1, "cmd": "dictation", "do": step.rawValue, "mode": mode.rawValue]
        case .run(let action): ["v": 1, "cmd": "run", "action": action.rawValue]
        case .prompt(let id): ["v": 1, "cmd": "prompt", "id": id]
        }
    }

    // MARK: Status (Tippi → plugin)

    static func encode(_ s: Status) -> [String: Any] {
        var o: [String: Any] = ["v": 1, "dictation": s.dictation.rawValue, "ready": s.ready,
                                "level": min(maxLevel, max(0, s.level)), "paused": s.paused,
                                "autocomplete": s.autocomplete, "language": s.language]
        if let src = s.source { o["source"] = src }
        o["prompts"] = s.prompts.prefix(maxPrompts).map { ["id": $0.id, "title": clean($0.title)] }
        o["modes"] = s.modes.prefix(maxModes).map { ["id": $0.id, "title": clean($0.title)] }
        return o
    }

    /// Plugin side: read a status. Texts are cleaned and cut again – the plugin trusts only the shape.
    static func parseStatus(_ payload: Data) -> Status? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], isNumberOne(obj["v"]),
              let state = (obj["dictation"] as? String).flatMap(DictationState.init(rawValue:)) else { return nil }
        var s = Status()
        s.dictation = state
        s.ready = obj["ready"] as? Bool ?? false
        s.level = min(maxLevel, max(0, (obj["level"] as? NSNumber)?.intValue ?? 0))
        s.paused = obj["paused"] as? Bool ?? false
        s.autocomplete = obj["autocomplete"] as? Bool ?? false
        s.language = (obj["language"] as? String).flatMap { isValidLanguage($0) ? $0 : nil } ?? "auto"
        s.source = (obj["source"] as? String).flatMap { ["standard", "mail", "mode", "inbox"].contains($0) ? $0 : nil }
        let items = { (key: String, limit: Int) -> [Item] in
            ((obj[key] as? [[String: Any]]) ?? []).prefix(limit).compactMap { o in
                guard let id = o["id"] as? String, isValidID(id), let t = o["title"] as? String else { return nil }
                let title = clean(t)
                return title.isEmpty ? nil : Item(id: id, title: title)
            }
        }
        s.prompts = items("prompts", maxPrompts)
        s.modes = items("modes", maxModes).filter { ModeSlot(rawValue: $0.id) != nil }
        return s
    }

    static func isAck(_ payload: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
        return isNumberOne(obj["v"]) && obj["ok"] as? Bool == true
    }

    // MARK: Frames

    enum Next: Equatable {
        case needMore
        case invalid
        case message(Data)
    }

    static func frame(_ obj: [String: Any], max: Int = maxFrame) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: obj), json.count <= max else { return nil }
        var length = UInt32(json.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(json)
        return data
    }

    /// Take the next complete frame off `buffer`. Zero length or longer than `max` → invalid.
    static func nextFrame(_ buffer: inout Data, max: Int = maxFrame) -> Next {
        guard buffer.count >= 4 else { return .needMore }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length <= max else { return .invalid }
        guard buffer.count >= 4 + length else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(payload)
    }

    /// Is the plugin version older than Tippi's? Compared number by number; unreadable counts as outdated.
    static func isOutdated(plugin: String, current: String) -> Bool {
        let parts = { (s: String) -> [Int]? in
            guard s.range(of: #"^\d{1,6}(\.\d{1,6}){0,3}$"#, options: .regularExpression) != nil else { return nil }
            return s.split(separator: ".").compactMap { Int($0) }
        }
        guard let p = parts(plugin) else { return true }
        guard let c = parts(current) else { return false }
        let n = Swift.max(p.count, c.count)
        let pad = { (a: [Int]) in a + Array(repeating: 0, count: n - a.count) }
        return pad(p).lexicographicallyPrecedes(pad(c))
    }
}
