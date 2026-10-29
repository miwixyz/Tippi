import XCTest
@testable import Tippi

/// docs/SECURE-DESIGN-befehlskanal.md B5/B6: Der Befehlskanal der Bild-Testkopie nimmt nur die feste Befehlsliste an.
final class DebugCommandTests: XCTestCase {
    private func parse(_ json: String) -> DebugCommand? { DebugCommand.parse(Data(json.utf8)) }

    func testAcceptsTheFixedCommands() {
        XCTAssertEqual(parse(#"{"v":1,"id":"abc123","cmd":"status"}"#), DebugCommand(id: "abc123", kind: .status))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"einstellungen"}"#)?.kind, .snapshot(window: "einstellungen"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"hilfe"}"#)?.kind, .snapshot(window: "hilfe"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"ueber"}"#)?.kind, .snapshot(window: "ueber"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":"dark"}"#)?.kind, .appearance("dark"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":"light"}"#)?.kind, .appearance("light"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":"system"}"#)?.kind, .appearance("system"))
    }

    func testRejectsWindowsWithRealContent() {
        // Reiter und Fenster, die im echten Tippi echte Inhalte zeigen (B5).
        for window in ["anbieter", "prompts", "snippets", "verlauf", "diktat", "autovervollstaendigung",
                       "kurzbefehle", "berechtigungen", "notizen", "uebersetzen", "emoji", "Einstellungen"] {
            XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"\#(window)"}"#), window)
        }
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"snapshot"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":1}"#))
    }

    func testRejectsEverythingElse() {
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"quit"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":"rot"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":1}"#))
        // Version: Zahl 1, kein Wahrheitswert, keine 2.
        XCTAssertNil(parse(#"{"v":true,"id":"a","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":2,"id":"a","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"id":"a","cmd":"status"}"#))
        XCTAssertNil(parse("kein json"))
        XCTAssertNil(parse("[1,2]"))
    }

    func testIDCannotEscapeTheAnswerFolder() {
        // Die id wird Dateiname – nur Buchstaben und Ziffern, 1–32 Zeichen.
        XCTAssertNil(parse(#"{"v":1,"id":"../x","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a/b","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"ä","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":7,"cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"\#(String(repeating: "a", count: 33))","cmd":"status"}"#))
        XCTAssertNotNil(parse(#"{"v":1,"id":"\#(String(repeating: "a", count: 32))","cmd":"status"}"#))
    }

    func testFrameLimits() throws {
        // Hin und zurück: Rahmen = 4 Byte Länge + JSON.
        var buffer = try XCTUnwrap(DebugCommand.frame(["v": 1, "id": "a", "cmd": "status"]))
        guard case .message(let payload) = DebugCommand.nextFrame(&buffer) else { return XCTFail("kein Rahmen") }
        XCTAssertEqual(DebugCommand.parse(payload)?.kind, .status)
        XCTAssertTrue(buffer.isEmpty)
        // Unvollständig → warten; Länge 0 oder über 4 KB → ungültig (Verbindung zu).
        var short = Data([0, 0, 0, 10, 0x7B])
        XCTAssertEqual(DebugCommand.nextFrame(&short), .needMore)
        var empty = Data([0, 0, 0, 0])
        XCTAssertEqual(DebugCommand.nextFrame(&empty), .invalid)
        var huge = withUnsafeBytes(of: UInt32(DebugCommand.maxFrame).bigEndian) { Data($0) }
        XCTAssertEqual(DebugCommand.nextFrame(&huge), .invalid)
        XCTAssertNil(DebugCommand.frame(["x": String(repeating: "a", count: DebugCommand.maxFrame)]))
    }

    func testTestRunIsNotTheBildKopie() {
        // Im Testlauf ist die Kennung nicht die der Bild-Kopie: Pfade und Schlüsselbund bleiben die echten.
        XCTAssertFalse(BildKopie.isActive)
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(BildKopie.applicationSupport, real)
        XCTAssertEqual(BildKopie.keychainService("com.tippi.app"), "com.tippi.app")
        XCTAssertEqual(KeychainStore.service, "com.tippi.app")
    }
}
