import CryptoKit
import XCTest
@testable import Tippi

/// Desk gadget (Tippi-Firmware 0.9): signature must match the firmware, only the state word goes out.
@MainActor
final class DeskDeviceTests: XCTestCase {

    func testSignatureMatchesFirmwareFormat() {
        // Same input as tippi-firmware tools/zustand_senden.py: HMAC-SHA256(key, "<time>\n" + body), lower hex
        let body = DeskDeviceSettings.body(.denkt)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"z":"denkt"}"#)
        let sig = DeskDeviceSettings.signature(key: "k", time: 1_800_000_000, body: body)
        let expected = HMAC<SHA256>.authenticationCode(for: Data("1800000000\n{\"z\":\"denkt\"}".utf8),
                                                       using: SymmetricKey(data: Data("k".utf8)))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(sig, expected)
        XCTAssertEqual(sig.count, 64)
    }

    func testStateMapping() {
        XCTAssertEqual(DeskDeviceSettings.state(for: .recording(URL(fileURLWithPath: "/tmp/x")), previous: .idle), .hoert)
        XCTAssertEqual(DeskDeviceSettings.state(for: .transcribing, previous: nil), .denkt)
        XCTAssertEqual(DeskDeviceSettings.state(for: .idle, previous: .transcribing), .fertig)
        XCTAssertEqual(DeskDeviceSettings.state(for: .idle, previous: .recording(URL(fileURLWithPath: "/tmp/x"))), .ruhe,
                       "cancelled recording is not „done“")
    }

    func testHostAndKeyChecks() {
        XCTAssertEqual(DeskDeviceSettings.validHost(" tippi.local "), "tippi.local")
        XCTAssertNotNil(DeskDeviceSettings.validHost("192.168.10.139"))
        XCTAssertNil(DeskDeviceSettings.validHost("http://tippi.local"))
        XCTAssertNil(DeskDeviceSettings.validHost("tippi.local/zustand"))
        XCTAssertNil(DeskDeviceSettings.validHost("user@tippi.local"))
        XCTAssertNil(DeskDeviceSettings.validHost(""))
        XCTAssertTrue(DeskDeviceSettings.validKey(String(repeating: "a", count: 40)))
        XCTAssertFalse(DeskDeviceSettings.validKey("kurz"))
        XCTAssertFalse(DeskDeviceSettings.validKey(String(repeating: "a", count: 39) + " "))
    }
}
