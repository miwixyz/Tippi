import Foundation

/// Namens-Trefferquote für die Vokabular-Messung (2026-11-21).
///
/// Zählt je Begriff, wie oft er im Referenztext steht und wie oft in der
/// Erkennung, normalisiert wie die Wortfehlerrate (Kleinschreibung, Satzzeichen
/// weg, Begriffe aus mehreren Wörtern als Wortfolge). Treffer = so oft, wie der
/// Begriff in beiden steht. Falsch eingesetzt = so oft, wie er in der Erkennung
/// häufiger steht als in der Referenz — genau der Schaden, den Boosting
/// anrichten kann (ein richtig gehörtes Wort wird zum Namen „verbessert“).
public enum Namen {
    public struct Bilanz: Equatable {
        public var soll: Int
        public var treffer: Int
        public var falsch: Int

        public init(soll: Int = 0, treffer: Int = 0, falsch: Int = 0) {
            self.soll = soll
            self.treffer = treffer
            self.falsch = falsch
        }

        public static func + (lhs: Bilanz, rhs: Bilanz) -> Bilanz {
            Bilanz(soll: lhs.soll + rhs.soll, treffer: lhs.treffer + rhs.treffer, falsch: lhs.falsch + rhs.falsch)
        }
    }

    public static func zaehle(referenz: String, erkannt: String, begriffe: [String]) -> Bilanz {
        let ref = Wortfehler.woerter(referenz)
        let hyp = Wortfehler.woerter(erkannt)
        var bilanz = Bilanz()
        for begriff in begriffe {
            let folge = Wortfehler.woerter(begriff)
            guard !folge.isEmpty else { continue }
            let r = vorkommen(folge, in: ref)
            let h = vorkommen(folge, in: hyp)
            bilanz.soll += r
            bilanz.treffer += min(r, h)
            bilanz.falsch += max(0, h - r)
        }
        return bilanz
    }

    /// Nicht überlappende Vorkommen der Wortfolge.
    static func vorkommen(_ folge: [String], in woerter: [String]) -> Int {
        guard folge.count <= woerter.count else { return 0 }
        var anzahl = 0
        var i = 0
        while i + folge.count <= woerter.count {
            if Array(woerter[i..<(i + folge.count)]) == folge {
                anzahl += 1
                i += folge.count
            } else {
                i += 1
            }
        }
        return anzahl
    }

    /// Vokabeldatei: eine Zeile je Begriff, optional Hörvarianten nach `:` mit
    /// Komma getrennt (`CINEWEB: Cineweb, Sinnweb`). `#` leitet Kommentare ein.
    public static func leseVokabular(_ text: String) -> [(begriff: String, varianten: [String])] {
        text.split(whereSeparator: \.isNewline).compactMap { roh in
            let zeile = roh.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let teile = zeile.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let begriff = teile[0].trimmingCharacters(in: .whitespaces)
            guard !begriff.isEmpty else { return nil }
            let varianten = teile.count > 1
                ? teile[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            return (begriff, varianten)
        }
    }
}
