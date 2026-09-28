import AppKit
import CoreGraphics
import XCTest
@testable import Tippi

/// Die frei belegbaren Übernahme-Tasten der Autovervollständigung
/// (docs/SECURE-DESIGN-autocomplete.md §3 „Tastatur → Tippi"): welche Taste der
/// Tap schluckt, welche Tasten überhaupt erlaubt sind, und dass Gespeichertes
/// beim Lesen geprüft wird. Eigene Klasse, weil `AutocompleteTests` sonst die
/// Längengrenze reißt. Nie `UserDefaults.standard`.
@MainActor
final class AutocompleteKeyTests: XCTestCase {

    private let suites = ThrowawayDefaults()

    override func setUp() {
        super.setUp()
        AutocompleteSettings.store = suites.make()
    }

    override func tearDown() {
        AutocompleteSettings.store = .standard
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Tap: welche Aktion

    /// Default = heutiges Verhalten: ⇥ allein übernimmt ein Wort.
    func testDefaultBindingsAreTabAndShiftTab() {
        let bindings = AutocompleteKeyBindings.default
        XCTAssertEqual(bindings.nextWord, KeyCombo(keyCode: 48, modifiers: []))
        XCTAssertEqual(bindings.wholeSuggestion, KeyCombo(keyCode: 48, modifiers: [.shift]))
        let tab = AutocompleteKeyDecision.tabKeyCode
        XCTAssertEqual(AutocompleteKeyDecision.action(keyCode: tab, flags: [], suggestionVisible: true, bindings: bindings),
                       .nextWord)
        XCTAssertEqual(AutocompleteKeyDecision.action(keyCode: tab, flags: .maskShift, suggestionVisible: true,
                                                      bindings: bindings), .wholeSuggestion)
        XCTAssertNil(AutocompleteKeyDecision.action(keyCode: tab, flags: .maskShift, suggestionVisible: false,
                                                    bindings: bindings))
    }

    /// Beide Aktionen mit eigenen Tasten: nur genau diese werden geschluckt,
    /// ⇥ läuft dann durch — und nichts ohne sichtbaren Vorschlag.
    func testCustomBindingsSwallowOnlyTheirKeys() {
        let bindings = AutocompleteKeyBindings(nextWord: KeyCombo(keyCode: 124, modifiers: []),          // →
                                               wholeSuggestion: KeyCombo(keyCode: 36, modifiers: [.command]))  // ⌘↩
        // Pfeiltasten kommen von macOS immer mit Fn- und Ziffernblock-Flag.
        let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
        XCTAssertEqual(AutocompleteKeyDecision.action(keyCode: 124, flags: arrowFlags, suggestionVisible: true,
                                                      bindings: bindings), .nextWord)
        XCTAssertEqual(AutocompleteKeyDecision.action(keyCode: 36, flags: .maskCommand, suggestionVisible: true,
                                                      bindings: bindings), .wholeSuggestion)
        XCTAssertFalse(AutocompleteKeyDecision.shouldSwallow(keyCode: 36, flags: [], suggestionVisible: true, bindings: bindings))
        XCTAssertFalse(AutocompleteKeyDecision.shouldSwallow(keyCode: 48, flags: [], suggestionVisible: true, bindings: bindings))
        XCTAssertFalse(AutocompleteKeyDecision.shouldSwallow(keyCode: 124, flags: [.maskShift, .maskSecondaryFn],
                                                             suggestionVisible: true, bindings: bindings))
        XCTAssertFalse(AutocompleteKeyDecision.shouldSwallow(keyCode: 124, flags: arrowFlags, suggestionVisible: false,
                                                             bindings: bindings))
    }

    func testEventFlagsMapToTheFourModifiers() {
        XCTAssertEqual(AutocompleteKeyDecision.modifiers(from: [.maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad]),
                       [.command])
        XCTAssertEqual(AutocompleteKeyDecision.modifiers(from: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
                       [.command, .control, .option, .shift])
        XCTAssertEqual(AutocompleteKeyDecision.modifiers(from: .maskAlphaShift), [])
    }

    // MARK: - Welche Tasten erlaubt sind

    private func problem(_ keyCode: UInt16, _ mods: NSEvent.ModifierFlags = []) -> AutocompleteKeyRules.Problem? {
        AutocompleteKeyRules.problem(KeyCombo(keyCode: keyCode, modifiers: mods))
    }

    func testSafeKeysAreAllowedWithoutModifier() {
        for keyCode: UInt16 in [48, 124, 125, 50, 10, 122, 96, 111] {   // ⇥ → ↓ ` ^ F1 F5 F12
            XCTAssertNil(problem(keyCode), "\(keyCode)")
        }
    }

    /// Buchstaben, Ziffern, Satzzeichen, Leertaste, ↩ — würden beim Tippen verschluckt.
    func testTypingKeysWithoutModifierAreRefused() {
        for keyCode: UInt16 in [0, 18, 47, 43, 49, 36, 51, 123, 126] {   // a 1 . , Space ↩ ⌫ ← ↑
            XCTAssertEqual(problem(keyCode), .typesText, "\(keyCode)")
        }
    }

    /// ⇧ oder ⌥ allein erzeugen Zeichen; ⌘/⌃ nicht.
    func testShiftOrOptionAloneStillTypesText() {
        XCTAssertEqual(problem(0, [.shift]), .typesText)            // ⇧A = „A"
        XCTAssertEqual(problem(37, [.option]), .typesText)          // ⌥L = „@"
        XCTAssertEqual(problem(50, [.shift]), .typesText)           // ⇧` = „~"
        XCTAssertNil(problem(0, [.command]))
        XCTAssertNil(problem(37, [.control]))                      // ⌃L
        XCTAssertNil(problem(36, [.command]))                       // ⌘↩
        XCTAssertNil(problem(48, [.shift]))                         // ⇧⇥
        XCTAssertNil(problem(124, [.option]))                       // ⌥→
    }

    func testEscapeIsNeverAllowed() {
        XCTAssertEqual(problem(53), .escape)
        XCTAssertEqual(problem(53, [.command]), .escape)
    }

    /// ⌃Space/⌃⌥Space (Eingabequelle) und Tippis eigene Hotkeys sind tabu —
    /// auch mit ⌘/⌃, wo sonst jede Taste geht.
    func testReservedShortcutsAreRefused() {
        XCTAssertEqual(problem(49, [.control]), .alreadyShortcut)
        XCTAssertEqual(problem(49, [.control, .option]), .alreadyShortcut)
        let mainHotkey = KeyCombo.default                                  // ⌥⌘T
        XCTAssertEqual(AutocompleteKeyRules.problem(mainHotkey, reserved: [mainHotkey]), .alreadyShortcut)
        XCTAssertNil(AutocompleteKeyRules.problem(mainHotkey, reserved: []))
        XCTAssertNil(AutocompleteKeyRules.problem(KeyCombo(keyCode: 49, modifiers: [.command, .control]),
                                                  reserved: [mainHotkey]))
    }

    /// Die Taste der anderen Aktion wählen tauscht die beiden.
    func testSwapWhenPickingTheOtherActionsKey() {
        let result = AutocompleteKeyBindings.default.assigning(AutocompleteKeyBindings.defaultWholeSuggestion,
                                                               to: .nextWord)
        XCTAssertTrue(result.swapped)
        XCTAssertEqual(result.bindings.nextWord, AutocompleteKeyBindings.defaultWholeSuggestion)
        XCTAssertEqual(result.bindings.wholeSuggestion, AutocompleteKeyBindings.defaultNextWord)
        let back = result.bindings.assigning(AutocompleteKeyBindings.defaultWholeSuggestion, to: .wholeSuggestion)
        XCTAssertTrue(back.swapped)
        XCTAssertEqual(back.bindings, .default)
    }

    func testSwapOnlyOnCollision() {
        let right = KeyCombo(keyCode: 124, modifiers: [])
        let plain = AutocompleteKeyBindings.default.assigning(right, to: .wholeSuggestion)
        XCTAssertFalse(plain.swapped)
        XCTAssertEqual(plain.bindings.nextWord, AutocompleteKeyBindings.defaultNextWord)
        XCTAssertEqual(plain.bindings.wholeSuggestion, right)
        let same = AutocompleteKeyBindings.default.assigning(AutocompleteKeyBindings.defaultNextWord, to: .nextWord)
        XCTAssertFalse(same.swapped)
        XCTAssertEqual(same.bindings, .default)
    }

    /// Gespeichertes wird beim Lesen geprüft — eine von Hand gesetzte Tipp-Taste
    /// oder Doppelbelegung darf nie in den Tap gelangen.
    func testSanitizedBindingsFallBackToDefaults() {
        let letterA = KeyCombo(keyCode: 0, modifiers: [])
        XCTAssertEqual(AutocompleteKeyBindings.sanitized(nextWord: nil, wholeSuggestion: nil), .default)
        XCTAssertEqual(AutocompleteKeyBindings.sanitized(nextWord: letterA, wholeSuggestion: letterA), .default)
        let shiftTab = AutocompleteKeyBindings.defaultWholeSuggestion
        let swapped = AutocompleteKeyBindings.sanitized(nextWord: shiftTab, wholeSuggestion: shiftTab)
        XCTAssertEqual(swapped.nextWord, shiftTab)
        XCTAssertEqual(swapped.wholeSuggestion, AutocompleteKeyBindings.defaultNextWord)
        let right = KeyCombo(keyCode: 124, modifiers: [])
        XCTAssertEqual(AutocompleteKeyBindings.sanitized(nextWord: right, wholeSuggestion: nil).nextWord, right)
    }

    func testKeyHintNamesTheConfiguredKeys() {
        let hint = AutocompleteSuggestionPanel.keyHint(.default)
        XCTAssertTrue(hint.contains("⇥"), hint)
        XCTAssertTrue(hint.contains("⇧⇥"), hint)
        let custom = AutocompleteSuggestionPanel.keyHint(
            AutocompleteKeyBindings(nextWord: KeyCombo(keyCode: 124, modifiers: []),
                                    wholeSuggestion: KeyCombo(keyCode: 125, modifiers: [])))
        XCTAssertTrue(custom.contains("→") && custom.contains("↓"), custom)
    }

    // MARK: - Einstellungen (über `store`, nie `.standard`)

    func testKeyBindingsDefaultAndRoundTrip() {
        XCTAssertEqual(AutocompleteSettings.keyBindings, .default)
        let custom = AutocompleteKeyBindings(nextWord: KeyCombo(keyCode: 124, modifiers: []),
                                             wholeSuggestion: KeyCombo(keyCode: 36, modifiers: [.command]))
        AutocompleteSettings.keyBindings = custom
        XCTAssertEqual(AutocompleteSettings.keyBindings, custom)
    }

    /// Eine von Hand in die Plist geschriebene Buchstabentaste wird nie benutzt.
    func testStoredTypingKeyIsIgnored() throws {
        let data = try JSONEncoder().encode(KeyCombo(keyCode: 0, modifiers: []))
        AutocompleteSettings.store.set(data, forKey: "tippi.autocomplete.key.nextWord.v1")
        XCTAssertEqual(AutocompleteSettings.keyBindings.nextWord, AutocompleteKeyBindings.defaultNextWord)
    }

    /// Feststell-/Fn-Bits aus einer bearbeiteten Plist werden beim Lesen entfernt.
    func testStoredModifierNoiseIsStripped() throws {
        let noisy = #"{"keyCode":124,"modifiersRaw":\#(NSEvent.ModifierFlags([.capsLock, .function]).rawValue)}"#
        AutocompleteSettings.store.set(Data(noisy.utf8), forKey: "tippi.autocomplete.key.nextWord.v1")
        XCTAssertEqual(AutocompleteSettings.keyBindings.nextWord, KeyCombo(keyCode: 124, modifiers: []))
    }

    func testKeyHintIsShownByDefault() {
        XCTAssertTrue(AutocompleteSettings.showKeyHint)
        AutocompleteSettings.showKeyHint = false
        XCTAssertFalse(AutocompleteSettings.showKeyHint)
    }
}
