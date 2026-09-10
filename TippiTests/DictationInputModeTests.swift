import XCTest
@testable import Tippi

/// Covers the persisted half of the tap-or-hold dictation gesture: defaults,
/// round-tripping, and — most importantly — that adding the new trigger case did
/// not break decoding of hot keys users already saved.
///
/// NOT covered here: the gesture timing itself (press → threshold → hold →
/// release). That path lives behind a CGEventTap and a Timer inside
/// `HotkeyManager.handleFlagsChanged`, which cannot be driven from a unit test
/// without extracting it into a pure type first. It is verified manually —
/// see docs/HANDOVER.md.
@MainActor
final class DictationInputModeTests: XCTestCase {

    private let modeKey = "dictation.inputMode.v1"
    private let modifierKey = "dictation.tapOrHold.modifier.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: modifierKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: modifierKey)
        super.tearDown()
    }

    // MARK: - Defaults

    /// The whole point of defaulting to `.combo`: someone who already configured
    /// a dictation hot key must not silently get a different input style after
    /// updating.
    func testDefaultModeIsComboSoExistingInstallsAreUnaffected() {
        XCTAssertEqual(DictationSettings.mode, .combo)
    }

    func testDefaultTapOrHoldModifierIsRightShift() {
        XCTAssertEqual(DictationSettings.tapOrHoldModifier, .rightShift)
    }

    /// A garbage value in UserDefaults must fall back, not crash or disable the
    /// hot key.
    func testUnknownStoredValuesFallBackToDefaults() {
        UserDefaults.standard.set("nonsense", forKey: modeKey)
        UserDefaults.standard.set("nonsense", forKey: modifierKey)
        XCTAssertEqual(DictationSettings.mode, .combo)
        XCTAssertEqual(DictationSettings.tapOrHoldModifier, .rightShift)
    }

    // MARK: - Persistence

    func testModeRoundTrips() {
        DictationSettings.mode = .tapOrHold
        XCTAssertEqual(DictationSettings.mode, .tapOrHold)
        DictationSettings.mode = .combo
        XCTAssertEqual(DictationSettings.mode, .combo)
    }

    func testModifierRoundTrips() {
        DictationSettings.tapOrHoldModifier = .leftCommand
        XCTAssertEqual(DictationSettings.tapOrHoldModifier, .leftCommand)
    }

    /// Every modifier offered in the settings picker must survive a round trip —
    /// the picker iterates `allCases`, so a non-round-tripping case would show up
    /// as a selection that silently resets.
    func testEveryOfferedModifierRoundTrips() {
        for mod in ModifierKey.allCases {
            DictationSettings.tapOrHoldModifier = mod
            XCTAssertEqual(DictationSettings.tapOrHoldModifier, mod, "\(mod) did not round-trip")
        }
    }

    // MARK: - Trigger encoding

    func testTapOrHoldTriggerRoundTripsThroughCodable() throws {
        let trigger = HotkeyTrigger.tapOrHold(modifier: .rightShift, holdThresholdMs: 250)
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        XCTAssertEqual(decoded, trigger)
    }

    /// Adding an enum case must not break hot keys saved by earlier versions.
    func testPreviouslySavedTriggersStillDecode() throws {
        let existing: [HotkeyTrigger] = [
            .doubleTap(modifier: .rightOption, thresholdMs: 300),
            .hold(modifier: .leftControl, durationMs: 500),
            .combo(keyCode: 17, carbonModifierFlags: 256)
        ]
        for trigger in existing {
            let data = try JSONEncoder().encode(trigger)
            let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
            XCTAssertEqual(decoded, trigger, "\(trigger) no longer decodes")
        }
    }

    func testTapOrHoldSummaryNamesTheKey() {
        let summary = HotkeyTrigger.tapOrHold(modifier: .rightShift, holdThresholdMs: 250).summary
        XCTAssertTrue(summary.contains(ModifierKey.rightShift.displayName), "summary was: \(summary)")
    }

    // MARK: - Safety constants

    /// A stuck key must not record forever. The exact value is a judgement call;
    /// that it exists and is finite is not.
    func testHoldWatchdogIsFiniteAndReasonable() {
        XCTAssertGreaterThan(DictationSettings.maxHoldSeconds, 30)
        XCTAssertLessThanOrEqual(DictationSettings.maxHoldSeconds, 600)
    }

    /// Below a deliberate tap the gesture would fire holds constantly; far above
    /// it, holding would feel unresponsive.
    func testHoldThresholdSeparatesTapFromHold() {
        XCTAssertGreaterThanOrEqual(DictationSettings.holdThresholdMs, 120)
        XCTAssertLessThanOrEqual(DictationSettings.holdThresholdMs, 600)
    }
}
