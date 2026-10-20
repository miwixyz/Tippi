import XCTest
@testable import Tippi

/// Gnotchi (Notch-App der Familie, ab 0.2.0) zeigt Tippis Diktat in der Notch; Tippi blendet dann die eigene
/// Pille aus. Gnotchi prüft die Nachricht streng (Gnotchi SECURE-DESIGN G17) – das Format hier muss passen.
final class GnotchiBridgeTests: XCTestCase {

    func testPayloadFormat() {
        let rec = GnotchiBridge.payload(.recording, level: 0.42)
        XCTAssertEqual(rec["v"] as? Int, 1)
        XCTAssertEqual(rec["state"] as? String, "recording")
        XCTAssertEqual(rec["level"] as? Double ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertEqual(Set(rec.keys), ["v", "state", "level"], "nur Zustand und Pegel, nie Text")
        let tr = GnotchiBridge.payload(.transcribing, level: nil)
        XCTAssertEqual(tr["state"] as? String, "transcribing")
        XCTAssertNil(tr["level"])
        XCTAssertEqual(GnotchiBridge.payload(.idle, level: nil)["state"] as? String, "idle")
    }

    func testLevelIsClampedAndFinite() {
        XCTAssertEqual(GnotchiBridge.payload(.recording, level: 3)["level"] as? Double, 1)
        XCTAssertEqual(GnotchiBridge.payload(.recording, level: -1)["level"] as? Double, 0)
        XCTAssertEqual(GnotchiBridge.payload(.recording, level: Float.nan)["level"] as? Double, 0)
    }

    /// Erst Gnotchi 0.2.0 versteht die Meldung.
    func testVersionSupported() {
        XCTAssertTrue(GnotchiBridge.versionSupported("0.2.0"))
        XCTAssertTrue(GnotchiBridge.versionSupported("0.2.1"))
        XCTAssertTrue(GnotchiBridge.versionSupported("0.10"))
        XCTAssertTrue(GnotchiBridge.versionSupported("1.0"))
        XCTAssertFalse(GnotchiBridge.versionSupported("0.1.1"))
        XCTAssertFalse(GnotchiBridge.versionSupported("0.1.0"))
        XCTAssertFalse(GnotchiBridge.versionSupported(nil))
        XCTAssertFalse(GnotchiBridge.versionSupported("abc"))
    }

    /// Gnotchis Schalter „Tippi-Aufnahme anzeigen“: fehlt er, gilt „an“ (Gnotchis Werkseinstellung).
    func testSettingAllows() {
        XCTAssertTrue(GnotchiBridge.settingAllows(nil))
        XCTAssertTrue(GnotchiBridge.settingAllows(true))
        XCTAssertFalse(GnotchiBridge.settingAllows(false))
        XCTAssertTrue(GnotchiBridge.settingAllows("unsinn"), "fremder Typ → Werkseinstellung")
    }

    /// Mit Live-Vorschau bleibt Tippis Pille: Gnotchi zeigt nie Text.
    func testLivePreviewKeepsOwnPill() {
        XCTAssertTrue(GnotchiBridge.useGnotchi(livePreview: false, gnotchiReady: true))
        XCTAssertFalse(GnotchiBridge.useGnotchi(livePreview: true, gnotchiReady: true))
        XCTAssertFalse(GnotchiBridge.useGnotchi(livePreview: false, gnotchiReady: false))
    }
}
