import Foundation

/// Fügt die Zeilen einer Texterkennung zu Fließtext zusammen.
///
/// **Warum das mehr ist als „alle Umbrüche löschen":**
///
/// Die Texterkennung liefert jede *Bildschirmzeile* einzeln — das ist eine
/// Eigenschaft des Layouts, nicht des Textes. Ein Absatz, der im Bild über
/// fünf Zeilen läuft, kommt als fünf Zeilen zurück, und beim Einfügen steht
/// dann mitten im Satz ein Umbruch.
///
/// Ein pauschales Entfernen aller Umbrüche macht daraus aber eine einzige
/// Textwurst: Absätze verschwinden, Aufzählungen kleben aneinander,
/// Überschriften verschmelzen mit dem Folgesatz. Deshalb wird hier
/// unterschieden, **welcher Umbruch Layout ist und welcher Bedeutung trägt**.
enum RecognizedTextJoiner {

    /// Zeilen zu Absätzen verbinden. Umbrüche mit Bedeutung bleiben erhalten.
    static func join(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var out: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
            current = ""
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Leerzeile trennt Absätze — das ist ein Umbruch mit Bedeutung.
            if line.isEmpty {
                flush()
                continue
            }

            // Aufzählungen und nummerierte Listen beginnen immer neu. Sonst
            // hinge der zweite Punkt hinter dem ersten.
            if startsNewBlock(line) {
                flush()
                current = line
                continue
            }

            if current.isEmpty {
                current = line
                continue
            }

            // Am Satzende endet der Gedanke, nicht nur die Zeile.
            if endsSentence(current) {
                flush()
                current = line
                continue
            }

            // Trennstrich am Zeilenende: zusammenziehen OHNE Leerzeichen,
            // sonst wird aus „Ver- trag" ein Wort mit Lücke.
            if current.hasSuffix("-") && !current.hasSuffix(" -") {
                current = String(current.dropLast()) + line
            } else {
                current += " " + line
            }
        }
        flush()

        return out.joined(separator: "\n\n")
    }

    /// Zeilen, die erkennbar einen eigenen Block beginnen.
    private static func startsNewBlock(_ line: String) -> Bool {
        let bullets: [String] = ["- ", "• ", "* ", "– ", "— ", "· "]
        if bullets.contains(where: { line.hasPrefix($0) }) { return true }

        // „1. ", „2) ", „12. " — nummerierte Listen.
        let prefix = line.prefix(4)
        if let firstNonDigit = prefix.firstIndex(where: { !$0.isNumber }),
           firstNonDigit != prefix.startIndex,
           prefix[firstNonDigit] == "." || prefix[firstNonDigit] == ")" {
            return true
        }
        return false
    }

    /// Endet die Zeile so, dass ein Umbruch dahinter gewollt wirkt?
    ///
    /// Eine Abkürzung wie „z. B." endet ebenfalls mit Punkt, ist aber kein
    /// Satzende. Deshalb zählt nur ein Punkt nach einem längeren Wort — bei
    /// einem Zeichen davor ist es mit hoher Wahrscheinlichkeit eine Abkürzung.
    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        if last == "!" || last == "?" || last == ":" { return true }
        guard last == "." else { return false }

        let beforeDot = text.dropLast()
        guard let lastWord = beforeDot.components(separatedBy: .whitespaces).last else {
            return true
        }
        return lastWord.count > 2
    }
}
