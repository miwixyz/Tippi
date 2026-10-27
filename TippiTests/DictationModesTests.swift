import CoreGraphics
import XCTest
@testable import Tippi

/// Diktat-Modi: Erkennung der Zusatztaste, Werksbelegung, Speichern/Laden,
/// Auflösung inkl. gelöschtem Prompt. Das echte Halten der Tasten am System
/// (CGEventTap, Haltegrenze) ist hier nicht abgedeckt — nur am Gerät prüfbar.
@MainActor
final class DictationModesTests: XCTestCase {

    // Wegwerf-Ablage, NIE `.standard` (der Test-Host ist die installierte App).
    private let suites = ThrowawayDefaults()
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        store = suites.make()
        DictationSettings.store = store
    }

    override func tearDown() {
        DictationSettings.store = .standard
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Flags

    private let rightOption = CGEventFlags.maskAlternate.rawValue | 0x0040

    private func flags(_ raw: UInt64) -> CGEventFlags { CGEventFlags(rawValue: raw) }

    func testRightOptionAloneIsNoMode() {
        XCTAssertNil(DictationModes.slot(in: flags(rightOption), trigger: .rightOption))
        XCTAssertNil(DictationModes.slot(in: [], trigger: .rightOption))
    }

    func testShiftLeftOrRightIsShift() {
        let left = rightOption | CGEventFlags.maskShift.rawValue | 0x0002
        let right = rightOption | CGEventFlags.maskShift.rawValue | 0x0004
        XCTAssertEqual(DictationModes.slot(in: flags(left), trigger: .rightOption), .shift)
        XCTAssertEqual(DictationModes.slot(in: flags(right), trigger: .rightOption), .shift)
    }

    func testControlAndCommandBothSides() {
        let ctrlL = rightOption | CGEventFlags.maskControl.rawValue | 0x0001
        let ctrlR = rightOption | CGEventFlags.maskControl.rawValue | 0x2000
        let cmdL = rightOption | CGEventFlags.maskCommand.rawValue | 0x0008
        let cmdR = rightOption | CGEventFlags.maskCommand.rawValue | 0x0010
        XCTAssertEqual(DictationModes.slot(in: flags(ctrlL), trigger: .rightOption), .control)
        XCTAssertEqual(DictationModes.slot(in: flags(ctrlR), trigger: .rightOption), .control)
        XCTAssertEqual(DictationModes.slot(in: flags(cmdL), trigger: .rightOption), .command)
        XCTAssertEqual(DictationModes.slot(in: flags(cmdR), trigger: .rightOption), .command)
    }

    func testFnUsesSecondaryFnFlag() {
        let fnHeld = rightOption | CGEventFlags.maskSecondaryFn.rawValue
        XCTAssertEqual(DictationModes.slot(in: flags(fnHeld), trigger: .rightOption), .fn)
    }

    func testTwoExtraKeysAreAmbiguousAndGivePlainDictation() {
        let both = rightOption | CGEventFlags.maskShift.rawValue | 0x0002 | CGEventFlags.maskCommand.rawValue | 0x0008
        XCTAssertNil(DictationModes.slot(in: flags(both), trigger: .rightOption))
    }

    func testCapsLockAndLeftOptionAreNoSlot() {
        let caps = rightOption | CGEventFlags.maskAlphaShift.rawValue
        let leftOption = rightOption | 0x0020
        XCTAssertNil(DictationModes.slot(in: flags(caps), trigger: .rightOption))
        XCTAssertNil(DictationModes.slot(in: flags(leftOption), trigger: .rightOption))
    }

    func testWithoutDeviceBitsTheGenericFlagCounts() {
        let generic = CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
        XCTAssertEqual(DictationModes.slot(in: flags(generic), trigger: .rightOption), .shift)
    }

    /// Ist die Diktat-Taste selbst ein ⇧, zählt nur das ANDERE ⇧ als Zusatztaste.
    func testTriggerOwnGroupIsNotItsOwnSlot() {
        let rightShiftAlone = CGEventFlags.maskShift.rawValue | 0x0004
        let plusLeftShift = rightShiftAlone | 0x0002
        let genericOnly = CGEventFlags.maskShift.rawValue
        XCTAssertNil(DictationModes.slot(in: flags(rightShiftAlone), trigger: .rightShift))
        XCTAssertEqual(DictationModes.slot(in: flags(plusLeftShift), trigger: .rightShift), .shift)
        XCTAssertNil(DictationModes.slot(in: flags(genericOnly), trigger: .rightShift))
    }

    // MARK: - Belegung

    func testDefaultAssignments() {
        XCTAssertTrue(DictationModes.isEnabled)
        XCTAssertEqual(DictationModes.assignment(for: .shift), .improve)
        XCTAssertEqual(DictationModes.assignment(for: .control), .prompt(id: "defuse"))
        XCTAssertEqual(DictationModes.assignment(for: .command), .prompt(id: "addEmojis"))
        XCTAssertEqual(DictationModes.assignment(for: .fn), .empty)
    }

    func testDefaultPromptsExistAsBuiltIns() {
        let ids = Set(DemoPrompt.builtIn.map(\.id))
        XCTAssertTrue(ids.contains("defuse"))
        XCTAssertTrue(ids.contains("addEmojis"))
    }

    func testSaveAndLoadRoundTrip() throws {
        DictationModes.setAssignment(.prompt(id: "custom-ABC"), for: .fn)
        DictationModes.setAssignment(.empty, for: .shift)
        DictationModes.isEnabled = false
        XCTAssertEqual(DictationModes.assignment(for: .fn), .prompt(id: "custom-ABC"))
        XCTAssertEqual(DictationModes.assignment(for: .shift), .empty)
        XCTAssertEqual(DictationModes.assignment(for: .control), .prompt(id: "defuse"))
        XCTAssertFalse(DictationModes.isEnabled)

        let data = try XCTUnwrap(store.data(forKey: DictationModes.assignmentsKey))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        let slots = try XCTUnwrap(json["slots"] as? [String: String])
        XCTAssertEqual(slots["fn"], "prompt:custom-ABC")
        XCTAssertEqual(slots["shift"], "empty")
    }

    func testBrokenOrNewerDataFallsBackToDefaults() {
        XCTAssertEqual(DictationModes.decode(Data("kaputt".utf8)), DictationModes.defaultAssignments)
        let newer = Data(#"{"version":2,"slots":{"fn":"improve"}}"#.utf8)
        XCTAssertEqual(DictationModes.decode(newer), DictationModes.defaultAssignments)
        let unknownToken = Data(#"{"version":1,"slots":{"shift":"irgendwas","fn":"improve"}}"#.utf8)
        let decoded = DictationModes.decode(unknownToken)
        XCTAssertEqual(decoded[.shift], .improve)   // Werksbelegung für den unlesbaren Platz
        XCTAssertEqual(decoded[.fn], .improve)
    }

    func testStorageTokens() {
        for assignment in [DictationModeAssignment.empty, .improve, .prompt(id: "custom-1")] {
            XCTAssertEqual(DictationModeAssignment(storageToken: assignment.storageToken), assignment)
        }
        XCTAssertNil(DictationModeAssignment(storageToken: "prompt:"))
    }

    // MARK: - Auflösung

    private let sample = DemoPrompt(id: "custom-X", title: "Mein Prompt", symbol: "star",
                                    systemPrompt: "Do it.", transform: { $0 })

    func testResolveImprovePromptAndEmpty() {
        let improve = DictationModes.resolve(.improve, slot: .shift, lookup: { _ in nil })
        XCTAssertEqual(improve?.action, .improve)
        XCTAssertEqual(improve?.slot, .shift)
        XCTAssertNil(DictationModes.resolve(.empty, slot: .fn, lookup: { _ in nil }))

        let mode = DictationModes.resolve(.prompt(id: "custom-X"), slot: .fn,
                                          lookup: { $0 == "custom-X" ? self.sample : nil })
        XCTAssertEqual(mode?.title, "Mein Prompt")
        XCTAssertEqual(mode?.symbol, "star")
        XCTAssertEqual(mode?.action, .prompt(sample))
    }

    func testDeletedPromptMeansEmptySlot() {
        DictationModes.setAssignment(.prompt(id: "custom-gone"), for: .fn)
        XCTAssertNil(DictationModes.resolve(DictationModes.assignment(for: .fn), slot: .fn, lookup: { _ in nil }))
        // Die Belegung bleibt gespeichert, falls der Prompt (iCloud) später ankommt.
        XCTAssertEqual(DictationModes.assignment(for: .fn), .prompt(id: "custom-gone"))
    }

    func testSourceOnlyWithTapOrHoldAndMainSwitch() {
        let shiftHeld = flags(rightOption | CGEventFlags.maskShift.rawValue | 0x0002)
        DictationSettings.mode = .tapOrHold
        DictationSettings.tapOrHoldModifier = .rightOption
        XCTAssertEqual(DictationModes.source(for: shiftHeld).dictationMode?.action, .improve)
        XCTAssertEqual(DictationModes.source(for: flags(rightOption)), .standard)

        DictationModes.isEnabled = false
        XCTAssertEqual(DictationModes.source(for: shiftHeld), .standard)

        DictationModes.isEnabled = true
        DictationSettings.mode = .combo
        XCTAssertEqual(DictationModes.source(for: shiftHeld), .standard)
    }
}
