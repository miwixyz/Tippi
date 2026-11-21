import XCTest
@testable import Wortfehler

/// Gegenprobe für die Namenszählung: typische Fehlbilder müssen auffallen.
final class NamenTests: XCTestCase {
    let begriffe = ["Tippi", "CINEWEB", "Filmstudio Ottobrunn"]

    func testAllesGetroffen() {
        let b = Namen.zaehle(referenz: "Tippi und CINEWEB im Filmstudio Ottobrunn.",
                             erkannt: "tippi und Cineweb im Filmstudio Ottobrunn",
                             begriffe: begriffe)
        XCTAssertEqual(b, .init(soll: 3, treffer: 3, falsch: 0))
    }

    func testVerhoererZaehltAlsFehltreffer() {
        // „Tipi“ statt Tippi, „Sinn Web“ statt CINEWEB.
        let b = Namen.zaehle(referenz: "Tippi schickt das an CINEWEB.", erkannt: "Tipi schickt das an Sinn Web.",
                             begriffe: begriffe)
        XCTAssertEqual(b, .init(soll: 2, treffer: 0, falsch: 0))
    }

    func testBoostingSetztNamenFalschEin() {
        // Gesprochen war „Tipps“, Boosting macht „Tippi“ daraus: muss als falsch zählen.
        let b = Namen.zaehle(referenz: "Ich habe zwei Tipps für dich.", erkannt: "Ich habe zwei Tippi für dich.",
                             begriffe: begriffe)
        XCTAssertEqual(b, .init(soll: 0, treffer: 0, falsch: 1))
    }

    func testMehrwortBegriffNurHalbErkannt() {
        let b = Namen.zaehle(referenz: "im Filmstudio Ottobrunn", erkannt: "im Filmstudio Otto Brunn",
                             begriffe: begriffe)
        XCTAssertEqual(b, .init(soll: 1, treffer: 0, falsch: 0))
    }

    func testDoppeltesVorkommen() {
        let b = Namen.zaehle(referenz: "Tippi, Tippi!", erkannt: "Tippi Tipi", begriffe: begriffe)
        XCTAssertEqual(b, .init(soll: 2, treffer: 1, falsch: 0))
    }

    func testVokabeldatei() {
        let v = Namen.leseVokabular("""
        # Kommentar
        Tippi: Tipi, Tippy
        CINEWEB

        Filmstudio Ottobrunn   # zwei Wörter
        """)
        XCTAssertEqual(v.map(\.begriff), ["Tippi", "CINEWEB", "Filmstudio Ottobrunn"])
        XCTAssertEqual(v[0].varianten, ["Tipi", "Tippy"])
        XCTAssertEqual(v[1].varianten, [])
    }
}
