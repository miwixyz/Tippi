import CoreGraphics
import XCTest
@testable import Tippi

/// Alternativen mitten im Wort (↓, 1–3). Rein logisch — kein Server, kein Tap,
/// nie `UserDefaults.standard`.
@MainActor
final class AutocompleteAlternativesTests: XCTestCase {

    typealias Alt = AutocompleteAlternatives
    private let bindings = AutocompleteKeyBindings.default

    private func decide(_ keyCode: Int64, _ flags: CGEventFlags = [], visible: Bool = true,
                        seed: Bool = true, list: Int = 0,
                        bindings: AutocompleteKeyBindings = .default) -> Alt.KeyDecision {
        Alt.decide(keyCode: keyCode, flags: flags, suggestionVisible: visible, seedAvailable: seed,
                   listCount: list, bindings: bindings)
    }

    // MARK: Tasten

    func testDownArrowShowsOnlyWithVisibleSuggestionAndSeed() {
        XCTAssertEqual(decide(125), .show)
        XCTAssertEqual(decide(125, visible: false), .none)
        XCTAssertEqual(decide(125, seed: false), .none, "am Wortanfang keine Alternativen")
        XCTAssertEqual(decide(125, .maskShift), .none, "⇧↓ markiert Text — nie abfangen")
    }

    func testOwnAcceptKeyOnDownArrowWins() {
        let onDown = AutocompleteKeyBindings(nextWord: KeyCombo(keyCode: 125, modifiers: []),
                                             wholeSuggestion: AutocompleteKeyBindings.defaultWholeSuggestion)
        XCTAssertEqual(decide(125, bindings: onDown), .none)
    }

    func testDigitsChooseOnlyWhileListIsOpen() {
        XCTAssertEqual(decide(18, list: 3), .choose(0))
        XCTAssertEqual(decide(84, list: 3), .choose(1), "Ziffernblock 2")
        XCTAssertEqual(decide(20, list: 3), .choose(2))
        XCTAssertEqual(decide(20, list: 2), .close, "3 gibt es bei zwei Wörtern nicht")
        XCTAssertEqual(decide(18, list: 0), .none, "ohne Liste bleibt 1 eine 1")
        XCTAssertEqual(decide(18, .maskCommand, list: 3), .close, "⌘1 ist ein Kurzbefehl, keine Wahl")
    }

    func testAnyOtherKeyClosesTheList() {
        XCTAssertEqual(decide(0, list: 3), .close)       // „a"
        XCTAssertEqual(decide(53, list: 3), .close)      // Esc
        XCTAssertEqual(decide(125, list: 3), .close)     // ↓ noch einmal
    }

    // MARK: Wörter

    func testFirstWordIsTypedStartPlusRestOfWord() {
        XCTAssertEqual(Alt.firstWord(started: "zw", suggestion: "ingen, viel zu raten."), "zwingen")
        XCTAssertEqual(Alt.firstWord(started: "Te", suggestion: "sts"), "Tests")
    }

    func testCandidateBecomesWholeWord() {
        XCTAssertEqual(Alt.word(open: " zw", started: "zw", piece: " zwar", continuation: " nicht", cutAtLength: false), "zwar")
        XCTAssertEqual(Alt.word(open: " zw", started: "zw", piece: " zwe", continuation: "ite Woche", cutAtLength: true), "zweite")
    }

    func testCandidateNotCoveringTheTypedStartIsDropped() {
        XCTAssertNil(Alt.word(open: " zw", started: "zw", piece: " z", continuation: "wingen", cutAtLength: false))
        XCTAssertNil(Alt.word(open: "", started: "", piece: " Kino", continuation: "", cutAtLength: false))
    }

    func testWordReachingTheLengthCutIsDropped() {
        // mlx-lm hängt, wenn die nächste Anfrage genau „vorige + ganze Antwort" ist.
        XCTAssertNil(Alt.word(open: " Re", started: "Re", piece: " Rech", continuation: "enleistungsgren", cutAtLength: true))
        XCTAssertEqual(Alt.word(open: " Re", started: "Re", piece: " Rech", continuation: "enleistung", cutAtLength: false),
                       "Rechenleistung")
    }

    func testListKeepsFirstAndDropsDuplicates() {
        XCTAssertEqual(Alt.list(first: "zwingen", others: ["Zwingen", "zwar", "zweite", "zwölf"]),
                       ["zwingen", "zwar", "zweite"])
        XCTAssertEqual(Alt.list(first: "zwingen", others: []), ["zwingen"])
    }

    func testLabelAndInsertion() {
        XCTAssertEqual(Alt.label(["zwingen", "zwar"]), "1 zwingen   2 zwar")
        XCTAssertEqual(Alt.insertion(word: "zwar", started: "zw"), "ar")
        XCTAssertEqual(Alt.insertion(word: "anders", started: "zw"), "")
    }

    // MARK: Anfrage

    func testTopLogprobsOnlyTogetherWithBias() throws {
        let server = try XCTUnwrap(URL(string: "http://127.0.0.1:8080"))
        let withBias = try XCTUnwrap(AutocompleteRequest.makeCompletion(
            server: server, model: "m", prompt: "p", maxTokens: 2, allowedTokenIDs: [1], topLogprobs: 8))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(withBias.httpBody)) as? [String: Any])
        XCTAssertEqual(body["top_logprobs"] as? Int, 8)
        let plain = try XCTUnwrap(AutocompleteRequest.makeCompletion(
            server: server, model: "m", prompt: "p", maxTokens: 6, topLogprobs: 8))
        let plainBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(plain.httpBody)) as? [String: Any])
        XCTAssertNil(plainBody["top_logprobs"])
    }

    func testParseAlternativeIDs() throws {
        let data = Data(#"{"choices":[{"text":" zwingen","logprobs":{"content":[{"id":5,"top_logprobs":[{"id":5},{"id":9},{"id":2}]}]}}]}"#.utf8)
        XCTAssertEqual(try XCTUnwrap(AutocompleteRequest.completion(from: data)).alternativeIDs, [5, 9, 2])
    }
}
