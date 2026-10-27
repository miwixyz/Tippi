import Foundation

/// Wortfehlerrate (WER): Mindestzahl an ersetzten, fehlenden und zusätzlichen
/// Wörtern, um die Erkennung in den Referenztext zu verwandeln, geteilt durch
/// die Wortzahl der Referenz.
///
/// Vor dem Vergleich normalisiert: Kleinschreibung, Satzzeichen weg. Gemessen
/// wird also, ob die Wörter stimmen, nicht Groß/Klein oder Komma — beides
/// richtet in Tippi ohnehin die KI-Nachbearbeitung bzw. das Einfügen. Zahlen
/// werden NICHT umgeschrieben: „drei“ gegen „3“ zählt als Fehler. Deshalb
/// Referenztexte so schreiben, wie das Modell sie ausgeben soll.
public enum Wortfehler {
    public struct Ergebnis: Equatable {
        public var fehler: Int
        public var referenzWoerter: Int

        public init(fehler: Int, referenzWoerter: Int) {
            self.fehler = fehler
            self.referenzWoerter = referenzWoerter
        }

        /// 0…∞ (mehr als 1 bei vielen zusätzlichen Wörtern). Leere Referenz:
        /// 0, wenn auch nichts erkannt wurde, sonst 1.
        public var rate: Double {
            guard referenzWoerter > 0 else { return fehler == 0 ? 0 : 1 }
            return Double(fehler) / Double(referenzWoerter)
        }

        public static func + (lhs: Ergebnis, rhs: Ergebnis) -> Ergebnis {
            Ergebnis(fehler: lhs.fehler + rhs.fehler, referenzWoerter: lhs.referenzWoerter + rhs.referenzWoerter)
        }
    }

    public static func woerter(_ text: String) -> [String] {
        let klein = text.lowercased()
        // Bindestrich und Apostroph trennen nicht anders als ein Leerzeichen:
        // „E-Mail“ und „E Mail“ sollen gleich zählen, „geht's“ und „gehts“ auch.
        let ohneZeichen = klein.unicodeScalars.map { skalar -> Character in
            if CharacterSet.letters.contains(skalar) || CharacterSet.decimalDigits.contains(skalar) {
                return Character(skalar)
            }
            if skalar == "'" || skalar == "’" { return "\u{0}" }
            return " "
        }
        return String(ohneZeichen)
            .replacingOccurrences(of: "\u{0}", with: "")
            .split(separator: " ")
            .map(String.init)
    }

    public static func vergleiche(referenz: String, erkannt: String) -> Ergebnis {
        let ref = woerter(referenz)
        let hyp = woerter(erkannt)
        return Ergebnis(fehler: abstand(ref, hyp), referenzWoerter: ref.count)
    }

    /// Levenshtein-Abstand über Wörter, zwei Zeilen Speicher.
    static func abstand(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var vorher = Array(0...b.count)
        var jetzt = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            jetzt[0] = i
            for j in 1...b.count {
                let kosten = a[i - 1] == b[j - 1] ? 0 : 1
                jetzt[j] = min(vorher[j] + 1, jetzt[j - 1] + 1, vorher[j - 1] + kosten)
            }
            swap(&vorher, &jetzt)
        }
        return vorher[b.count]
    }
}
