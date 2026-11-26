import XCTest
@testable import Tippi

/// Volltextsuche (Michael, 2026-11-26): Wörter in beliebiger Reihenfolge, ohne Groß-/Kleinschreibung
/// und Akzente.
final class NoteSearchTests: XCTestCase {
    func testTermsSplitAtWhitespace() {
        XCTAssertEqual(NoteSearch.terms("  Rechnung   Kino\n"), ["Rechnung", "Kino"])
        XCTAssertEqual(NoteSearch.terms("   "), [])
    }

    func testAllWordsInAnyOrder() {
        let text = "Kino Forsthof\nDie Rechnung kommt im Dezember."
        XCTAssertTrue(NoteSearch.matches(text, terms: NoteSearch.terms("rechnung kino")))
        XCTAssertFalse(NoteSearch.matches(text, terms: NoteSearch.terms("rechnung januar")))
    }

    /// Gegenprobe: eine reine Zeichenfolgen-Suche fände diese Notiz nicht.
    func testOldContiguousSearchWouldMiss() {
        let text = "Kino Forsthof\nDie Rechnung kommt im Dezember."
        XCTAssertFalse(text.localizedCaseInsensitiveContains("Rechnung Kino"))
        XCTAssertTrue(NoteSearch.matches(text, terms: NoteSearch.terms("Rechnung Kino")))
    }

    func testIgnoresCaseAndAccents() {
        XCTAssertTrue(NoteSearch.matches("Treffen im Café Résumé", terms: ["cafe", "RESUME"]))
        XCTAssertTrue(NoteSearch.matches("Mañana in San José", terms: ["manana", "jose"]))
        XCTAssertTrue(NoteSearch.matches("Größe prüfen", terms: ["große", "prufen"]))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(NoteSearch.matches("egal", terms: []))
    }

    func testExcerptStartsNearFirstHit() {
        let text = String(repeating: "Füllwort ", count: 10) + "Treffer am Ende"
        let excerpt = NoteSearch.excerpt(text, terms: ["treffer"])
        XCTAssertTrue(excerpt.hasPrefix("…"))
        XCTAssertTrue(excerpt.contains("Treffer am Ende"))
        XCTAssertFalse(excerpt.dropFirst().hasPrefix("llwort"), "Ausschnitt beginnt nicht mitten im Wort")
        XCTAssertLessThan(excerpt.count, text.count)
    }

    func testExcerptUnchangedWhenHitIsEarly() {
        XCTAssertEqual(NoteSearch.excerpt("Treffer gleich vorne", terms: ["gleich"]), "Treffer gleich vorne")
        XCTAssertEqual(NoteSearch.excerpt("Nur im Titel", terms: ["fehlt"]), "Nur im Titel")
    }

    func testHighlightMarksEveryHit() {
        let result = NoteSearch.highlighted("Kino und kino und Kíno", terms: ["kino"])
        let bold = result.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(result[$0.range].characters) }
        XCTAssertEqual(bold, ["Kino", "kino", "Kíno"])
    }
}
