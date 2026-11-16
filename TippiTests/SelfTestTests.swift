import XCTest
@testable import Tippi

/// Selbsttest der Bild-Testkopie (2026-11-16): Ein gescheiterter Schritt muss die Gesamtantwort kippen,
/// sonst meldet `tippictl selftest` Exit 0 trotz FAIL. Die Schritte selbst laufen nur in der Kopie.
@MainActor
final class SelfTestTests: XCTestCase {
    func testAllStepsPassingGivesPassed() {
        let answer = SelfTest.answer([.init(name: "a", ok: true, detail: "x"), .init(name: "b", ok: true, detail: "y")])
        XCTAssertEqual(answer["bestanden"] as? Bool, true)
        XCTAssertEqual((answer["schritte"] as? [[String: Any]])?.count, 2)
    }

    func testOneFailingStepFailsTheWhole() {
        let answer = SelfTest.answer([.init(name: "a", ok: true, detail: "x"), .init(name: "b", ok: false, detail: "y")])
        XCTAssertEqual(answer["bestanden"] as? Bool, false)
        XCTAssertEqual(answer["ok"] as? Bool, true, "ok heißt: Befehl ausgeführt, nicht: bestanden")
    }

    func testNoStepsIsNotAPass() {
        XCTAssertEqual(SelfTest.answer([])["bestanden"] as? Bool, false)
    }
}
