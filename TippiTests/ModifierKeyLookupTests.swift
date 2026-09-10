import XCTest
@testable import Tippi

/// Covers resolving a raw virtual key code back to a modifier — the lookup the
/// recorder field depends on. If this is wrong, the field records the wrong key
/// and the hot key silently does nothing, which is exactly the failure that made
/// the picker unusable in the first place.
final class ModifierKeyLookupTests: XCTestCase {

    /// The concrete case from 2026-09-10: the setting said Left Control (59)
    /// while the key actually being pressed reported 55 — left Command. Pinning
    /// both keeps the two from ever being confused again.
    func testTheTwoKeysThatWereConfused() {
        XCTAssertEqual(ModifierKey.from(keyCode: 55), .leftCommand)
        XCTAssertEqual(ModifierKey.from(keyCode: 59), .leftControl)
        XCTAssertNotEqual(ModifierKey.from(keyCode: 55), ModifierKey.from(keyCode: 59))
    }

    /// Every modifier must resolve back to itself. A duplicated or shifted key
    /// code would make one key unreachable and silently hijack another.
    func testEveryModifierRoundTrips() {
        for key in ModifierKey.allCases {
            XCTAssertEqual(ModifierKey.from(keyCode: key.keyCode), key,
                           "\(key) did not round-trip via keyCode \(key.keyCode)")
        }
    }

    /// All eight key codes must be distinct — `from(keyCode:)` returns the first
    /// match, so a collision would make a key permanently unselectable.
    func testKeyCodesAreUnique() {
        let codes = ModifierKey.allCases.map(\.keyCode)
        XCTAssertEqual(Set(codes).count, ModifierKey.allCases.count,
                       "duplicate key codes: \(codes)")
    }

    /// Left and right of the same group must not share a code — the whole point
    /// of naming them separately is that they can be told apart.
    func testLeftAndRightAreDistinct() {
        XCTAssertNotEqual(ModifierKey.leftShift.keyCode, ModifierKey.rightShift.keyCode)
        XCTAssertNotEqual(ModifierKey.leftControl.keyCode, ModifierKey.rightControl.keyCode)
        XCTAssertNotEqual(ModifierKey.leftOption.keyCode, ModifierKey.rightOption.keyCode)
        XCTAssertNotEqual(ModifierKey.leftCommand.keyCode, ModifierKey.rightCommand.keyCode)
    }

    /// Ordinary keys must not resolve. Letter "A" is 0, Escape is 53, Return 36 —
    /// if any of these mapped to a modifier, the recorder would happily capture a
    /// key that can never drive the gesture.
    func testNonModifierKeyCodesReturnNil() {
        for code: UInt16 in [0, 36, 49, 53, 123, 126] {
            XCTAssertNil(ModifierKey.from(keyCode: code),
                         "keyCode \(code) must not resolve to a modifier")
        }
    }

    /// The values are Apple's kVK_* constants; pinning them documents that they
    /// are not free to renumber.
    func testMatchesAppleVirtualKeyCodes() {
        XCTAssertEqual(ModifierKey.leftCommand.keyCode, 0x37)
        XCTAssertEqual(ModifierKey.leftShift.keyCode, 0x38)
        XCTAssertEqual(ModifierKey.leftOption.keyCode, 0x3A)
        XCTAssertEqual(ModifierKey.leftControl.keyCode, 0x3B)
        XCTAssertEqual(ModifierKey.rightCommand.keyCode, 0x36)
        XCTAssertEqual(ModifierKey.rightShift.keyCode, 0x3C)
        XCTAssertEqual(ModifierKey.rightOption.keyCode, 0x3D)
        XCTAssertEqual(ModifierKey.rightControl.keyCode, 0x3E)
    }
}
