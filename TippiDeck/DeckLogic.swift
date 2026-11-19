/// Pure pieces of the Stream Deck plugin, compiled into the plugin and into TippiTests. In the tests `DeckWire` lives in
/// the app module; in the plugin it is compiled in directly.
#if DECK_IN_TESTS
@testable import Tippi
#endif

enum DeckDictKind: String { case dictation, mail, voiceNote, reply }
enum DeckPress: String { case toggle, hold }
enum DeckSwitch: String { case pause, autocomplete, language }

enum DeckLogic {

    /// Tools on a key – a subset of `DeckWire.Action`.
    static let tools: [DeckWire.Action] = [.popup, .translate, .emoji, .notes, .quickNotes, .screenText, .password]

    /// Ring step through a list of `count` entries from `current` (nil → first or last, by direction).
    static func step(count: Int, from current: Int?, by ticks: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return ticks >= 0 ? 0 : count - 1 }
        return ((current + ticks) % count + count) % count
    }

    /// At most two lines of about `width` characters, broken at a space (Stream Deck does not wrap key titles).
    static func wrap(_ s: String, width: Int = 9) -> String {
        guard s.count > width else { return s }
        let words = s.split(separator: " ").map(String.init)
        var first = ""
        var rest = words[...]
        while let w = rest.first, first.isEmpty || first.count + 1 + w.count <= width {
            first += first.isEmpty ? w : " " + w
            rest = rest.dropFirst()
        }
        let second = rest.joined(separator: " ")
        guard !second.isEmpty else { return first }
        return first + "\n" + (second.count > width + 2 ? String(second.prefix(width + 1)) + "…" : second)
    }

    /// Does the running dictation belong to this key kind?
    static func matches(_ kind: DeckDictKind, source: String?) -> Bool {
        switch kind {
        case .dictation: source == "standard" || source == "mode"
        case .mail: source == "mail"
        case .voiceNote: source == "inbox"
        case .reply: source == "reply"
        }
    }

    /// Key image of a dictation key: kind + state (`-off` without Tippi or with dictation off).
    static func dictationImage(_ kind: DeckDictKind, status s: DeckWire.Status?, connected: Bool) -> String {
        let base = switch kind {
        case .dictation: "key-mic"
        case .mail: "key-mail"
        case .voiceNote: "key-voicenote"
        case .reply: "key-reply"
        }
        guard connected, let s, s.ready else { return base + "-off" }
        guard matches(kind, source: s.source) else { return base }
        switch s.dictation {
        case .idle: return base
        case .recording: return base + "-rec"
        case .transcribing: return base + "-busy"
        }
    }
}
