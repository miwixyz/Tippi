import Foundation

/// Volltextsuche über Notizen (Michael, 2026-11-26): Jedes Suchwort muss irgendwo vorkommen,
/// die Reihenfolge ist egal („Rechnung Kino“ findet „Kino … Rechnung“). Groß-/Kleinschreibung
/// und Akzente zählen nicht („cafe“ findet „Café“). Bewusst ohne Suchindex: Die Notizen liegen
/// ohnehin im Speicher, ein Durchlauf reicht für einige Tausend Notizen.
/// Gleiche Logik wie `NoteSearch` in TippAI — Änderungen in beiden Apps nachziehen.
enum NoteSearch {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// Suchwörter aus der Eingabe, getrennt an Leerzeichen und Zeilenumbrüchen.
    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `true`, wenn jedes Suchwort im Text vorkommt. Ohne Suchwörter trifft alles.
    static func matches(_ text: String, terms: [String]) -> Bool {
        terms.allSatisfy { text.range(of: $0, options: options, locale: .current) != nil }
    }

    /// Ausschnitt ab kurz vor dem ersten Treffer, damit in der Liste sichtbar ist, warum die
    /// Notiz gefunden wurde. Liegt der Treffer schon am Anfang (oder gar nicht im Text), bleibt
    /// der Text unverändert.
    static func excerpt(_ text: String, terms: [String], lead: Int = 30) -> String {
        let first = terms
            .compactMap { text.range(of: $0, options: options, locale: .current) }
            .min { $0.lowerBound < $1.lowerBound }
        guard let first, text.distance(from: text.startIndex, to: first.lowerBound) > lead else {
            return text
        }
        var start = text.index(first.lowerBound, offsetBy: -lead)
        // Nicht mitten im Wort anfangen: zum nächsten Wortanfang vor dem Treffer vorrücken.
        if let space = text[start..<first.lowerBound].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }
        return "…" + text[start...]
    }

    /// Text mit fett gesetzten Treffern aller Suchwörter.
    static func highlighted(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        for term in terms {
            var from = text.startIndex
            while from < text.endIndex,
                  let found = text.range(of: term, options: options, range: from..<text.endIndex, locale: .current) {
                if let range = Range(found, in: result) {
                    result[range].inlinePresentationIntent = .stronglyEmphasized
                }
                from = found.upperBound
            }
        }
        return result
    }
}
