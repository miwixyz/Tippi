import AppKit
import CoreGraphics
import Foundation

// MARK: - Alternativen mitten im Wort (Labs, 2026-10-13)

/// Drei Wörter zur Auswahl, wenn der Vorschlag mitten im Wort nicht passt:
/// ↓ blendet sie ein, 1–3 setzt eines ein, jede andere Taste schließt die Liste.
///
/// **Warum (gemessen 2026-10-13, 40 Stellen mitten im Wort, Gemma 4 E2B):**
/// Das Zielwort war in 21 Fällen der Vorschlag selbst, in 27 Fällen unter den
/// drei wahrscheinlichsten Wörtern. Am Wortanfang nur 4 → 5 — deshalb nur
/// mitten im Wort. Vorbild: Cotypists „Word Alternatives".
///
/// **Wann gerechnet wird:** Die Kandidaten fürs erste Wortstück kommen ohne
/// Zusatzkosten aus dem ersten Schritt der Wortheilung (`top_logprobs`); zu
/// ganzen Wörtern ergänzt wird erst, wenn ↓ gedrückt wird (Michael: „per
/// Kurzbefehl").
enum AutocompleteAlternatives {
    /// ↓ — nur abgefangen, solange ein Vorschlag mitten im Wort sichtbar ist.
    static let showKeyCode: Int64 = 125
    /// 1, 2, 3 der Ziffernreihe (18–20, gleich auf deutscher und US-Tastatur) und
    /// des Ziffernblocks (83–85). Gemessen 2026-10-13: AppleScripts `keystroke "2"`
    /// kam nicht als Taste 19 an und wurde getippt; `key code 19` wählte richtig.
    static let choiceKeyCodes: [Int64: Int] = [18: 0, 19: 1, 20: 2, 83: 0, 84: 1, 85: 2]
    static let maxWords = 3
    /// So viele Kandidaten fürs erste Stück fragt die Wortheilung mit ab.
    static let candidatePieces = 8
    /// Wortstücke, um einen Kandidaten zum ganzen Wort zu ergänzen.
    static let wordTokens = 6

    /// Was nach dem gezeigten Vorschlag noch nötig ist, um Alternativen zu bilden.
    struct Seed: Equatable {
        /// Prompt bis vor das erste Wortstück.
        let prompt: String
        /// Offener Wortanfang, wie das Modell ihn sieht (" zw").
        let open: String
        /// Getippter Wortanfang ("zw").
        let started: String
        /// Wort des gezeigten Vorschlags ("zwingen").
        let firstWord: String
        /// Kandidaten fürs erste Stück, wahrscheinlichste zuerst.
        let pieces: [String]
    }

    enum KeyDecision: Equatable {
        case show
        case choose(Int)
        /// Liste offen, andere Taste: Liste schließen, Taste geht normal weiter.
        case close
        case none
    }

    private static let blockingModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// Reine Entscheidung für den Tastatur-Abfang. Eine eigene Übernahme-Taste
    /// auf ↓ hat Vorrang.
    static func decide(keyCode: Int64, flags: CGEventFlags, suggestionVisible: Bool,
                       seedAvailable: Bool, listCount: Int,
                       bindings: AutocompleteKeyBindings) -> KeyDecision {
        let plain = flags.isDisjoint(with: blockingModifiers)
        if listCount > 0 {
            if plain, let index = choiceKeyCodes[keyCode], index < listCount { return .choose(index) }
            return .close
        }
        guard suggestionVisible, seedAvailable, plain, keyCode == showKeyCode,
              AutocompleteKeyDecision.action(keyCode: keyCode, flags: flags,
                                             suggestionVisible: true, bindings: bindings) == nil
        else { return .none }
        return .show
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Das Wort des gezeigten Vorschlags: getippter Anfang + Rest bis Wortende.
    static func firstWord(started: String, suggestion: String) -> String {
        started + String(suggestion.prefix(while: isWordCharacter))
    }

    /// Ganzes Wort aus einem Kandidaten fürs erste Stück und dessen kurzer
    /// Fortsetzung — oder `nil`, wenn das Stück den getippten Anfang nicht
    /// abdeckt, oder wenn das Wort bis an die Längengrenze reicht: Dann ist es
    /// womöglich abgeschnitten, und übernommen wäre die nächste Anfrage genau
    /// „vorige Anfrage + Antwort" — der mlx-lm-Fall, der den Server aufhängt.
    static func word(open: String, started: String, piece: String,
                     continuation: String, cutAtLength: Bool) -> String? {
        guard !open.isEmpty, piece.hasPrefix(open) else { return nil }
        let combined = String(piece.dropFirst(open.count)) + continuation
        let wordPart = String(combined.prefix(while: isWordCharacter))
        if cutAtLength, wordPart.count == combined.count { return nil }
        return started + wordPart
    }

    /// Erstes Wort plus weitere, ohne Dubletten (Groß/klein egal), höchstens `maxWords`.
    static func list(first: String, others: [String]) -> [String] {
        var result: [String] = []
        for word in [first] + others where !word.isEmpty {
            if !result.contains(where: { $0.lowercased() == word.lowercased() }) { result.append(word) }
            if result.count == maxWords { break }
        }
        return result
    }

    /// Anzeige in der Vorschlagskapsel: „1 zwingen   2 zwar   3 zweite".
    static func label(_ words: [String]) -> String {
        words.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: "   ")
    }

    /// Was beim Wählen eingefügt wird: das Wort ohne den schon getippten Anfang.
    static func insertion(word: String, started: String) -> String {
        word.hasPrefix(started) ? String(word.dropFirst(started.count)) : ""
    }
}
