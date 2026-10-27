import XCTest
@testable import Wortfehler

/// Das Messwerkzeug selbst prüfen, bevor man ihm eine Zahl glaubt.
final class WortfehlerTests: XCTestCase {
    func testGleicherTextOhneFehler() {
        let e = Wortfehler.vergleiche(referenz: "Hallo Welt, wie geht es?", erkannt: "hallo welt wie geht es")
        XCTAssertEqual(e, .init(fehler: 0, referenzWoerter: 5))
        XCTAssertEqual(e.rate, 0)
    }

    func testErsetzungFehlendesUndZusaetzlichesWort() {
        // „morgen“ → „heute“ (ersetzt), „noch“ fehlt, „bitte“ zusätzlich: 3 Fehler auf 6 Wörter.
        let e = Wortfehler.vergleiche(referenz: "ich brauche die Datei noch morgen",
                                      erkannt: "ich brauche bitte die Datei heute")
        XCTAssertEqual(e.fehler, 3)
        XCTAssertEqual(e.referenzWoerter, 6)
        XCTAssertEqual(e.rate, 0.5, accuracy: 0.0001)
    }

    func testUmlauteUndBindestrichUndApostroph() {
        XCTAssertEqual(Wortfehler.woerter("Grüße per E-Mail, geht's?"), ["grüße", "per", "e", "mail", "gehts"])
    }

    func testZahlenWerdenNichtUmgeschrieben() {
        XCTAssertEqual(Wortfehler.vergleiche(referenz: "drei Tage", erkannt: "3 Tage").fehler, 1)
    }

    func testLeereFaelle() {
        XCTAssertEqual(Wortfehler.vergleiche(referenz: "", erkannt: "").rate, 0)
        XCTAssertEqual(Wortfehler.vergleiche(referenz: "", erkannt: "etwas").rate, 1)
        XCTAssertEqual(Wortfehler.vergleiche(referenz: "zwei Wörter", erkannt: "").rate, 1)
    }

    func testSummeUeberDateienIstGewichtetNichtGemittelt() {
        let kurz = Wortfehler.Ergebnis(fehler: 1, referenzWoerter: 2)     // 50 %
        let lang = Wortfehler.Ergebnis(fehler: 0, referenzWoerter: 98)    // 0 %
        XCTAssertEqual((kurz + lang).rate, 0.01, accuracy: 0.0001)
    }
}
