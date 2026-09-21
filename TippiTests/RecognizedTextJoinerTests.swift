import XCTest
@testable import Tippi

/// Prüft das Zusammenführen von OCR-Zeilen.
///
/// Die Fälle sind echten Erkennungsergebnissen nachgebaut, nicht erfunden:
/// Fließtext über mehrere Bildschirmzeilen, Aufzählungen, Silbentrennung am
/// Zeilenende, Überschrift vor Absatz. Genau an diesen Stellen unterscheidet
/// sich „Umbrüche zusammenführen" von „alle Umbrüche löschen".
final class RecognizedTextJoinerTests: XCTestCase {

    /// Der Grundfall: Ein Absatz, den das Layout über drei Zeilen gebrochen hat.
    func testJoinsWrappedSentence() {
        let input = """
        Der Vertrag läuft zunächst über
        zwölf Monate und verlängert sich
        automatisch um ein weiteres Jahr.
        """
        XCTAssertEqual(
            RecognizedTextJoiner.join(input),
            "Der Vertrag läuft zunächst über zwölf Monate und verlängert sich automatisch um ein weiteres Jahr."
        )
    }

    /// Silbentrennung: ohne Sonderbehandlung entstünde „Ver- trag".
    func testJoinsHyphenatedWord() {
        let input = "Die Kündigungsfrist beträgt drei Mo-\nnate zum Quartalsende."
        XCTAssertEqual(
            RecognizedTextJoiner.join(input),
            "Die Kündigungsfrist beträgt drei Monate zum Quartalsende."
        )
    }

    /// Ein Satzende ist ein Umbruch mit Bedeutung — hier wird NICHT verbunden.
    func testKeepsParagraphAfterSentenceEnd() {
        let input = "Erster Gedanke ist fertig.\nZweiter Gedanke beginnt hier."
        let result = RecognizedTextJoiner.join(input)
        XCTAssertTrue(result.contains("\n\n"), "Nach einem Satzende muss getrennt bleiben.")
        XCTAssertTrue(result.hasPrefix("Erster Gedanke ist fertig."))
    }

    /// „z. B." endet auch mit Punkt, ist aber kein Satzende.
    func testDoesNotSplitOnAbbreviation() {
        let input = "Mitzubringen sind Unterlagen, z.\nB. der Personalausweis."
        let result = RecognizedTextJoiner.join(input)
        XCTAssertFalse(result.contains("\n\n"),
                       "Eine Abkürzung darf keinen Absatz erzeugen.")
    }

    /// Aufzählungen: Jeder Punkt beginnt neu, sonst kleben sie aneinander.
    func testKeepsBulletsSeparate() {
        let input = """
        Benötigt werden:
        - Personalausweis
        - Meldebescheinigung
        - Nachweis über das Einkommen
        """
        let result = RecognizedTextJoiner.join(input)
        XCTAssertEqual(result.components(separatedBy: "- ").count - 1, 3,
                       "Alle drei Aufzählungspunkte müssen eigenständig bleiben.")
    }

    func testKeepsNumberedListSeparate() {
        let input = "1. Antrag ausfüllen\n2. Unterlagen beilegen\n3. Absenden"
        let result = RecognizedTextJoiner.join(input)
        XCTAssertTrue(result.contains("2. Unterlagen"))
        XCTAssertTrue(result.contains("\n\n2."), "Punkt 2 muss einen eigenen Block bilden.")
    }

    /// Leerzeilen trennen Absätze und müssen das weiterhin tun.
    func testKeepsExplicitParagraphs() {
        let input = "Erster Absatz\n\nZweiter Absatz"
        XCTAssertEqual(RecognizedTextJoiner.join(input), "Erster Absatz\n\nZweiter Absatz")
    }

    /// Eine Überschrift mit Doppelpunkt trägt einen gewollten Umbruch.
    func testKeepsBreakAfterColon() {
        let input = "Öffnungszeiten:\nMontag bis Freitag von 9 bis 17 Uhr"
        XCTAssertTrue(RecognizedTextJoiner.join(input).contains("\n\n"))
    }

    func testHandlesEmptyAndWhitespace() {
        XCTAssertEqual(RecognizedTextJoiner.join(""), "")
        XCTAssertEqual(RecognizedTextJoiner.join("   \n  \n "), "")
        XCTAssertEqual(RecognizedTextJoiner.join("Einzeiler"), "Einzeiler")
    }
}
