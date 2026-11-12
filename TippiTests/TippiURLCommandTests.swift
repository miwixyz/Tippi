import XCTest
@testable import Tippi

/// `tippi://` is reachable by any app and any web page — only the one
/// allowlisted URL may do anything (docs/SECURE-DESIGN-url-schema.md).
final class TippiURLCommandTests: XCTestCase {
    private func parse(_ string: String) -> TippiURLCommand? {
        guard let url = URL(string: string) else { return nil }
        return TippiURLCommand.parse(url)
    }

    func testAcceptsQuickNotes() {
        XCTAssertEqual(parse("tippi://schnellnotiz"), .openQuickNotes)
        XCTAssertEqual(parse("tippi://schnellnotiz/"), .openQuickNotes)
        XCTAssertEqual(parse("TIPPI://Schnellnotiz"), .openQuickNotes)
    }

    func testRefusesParametersAndExtras() {
        for string in [
            "tippi://schnellnotiz?text=hallo",
            "tippi://schnellnotiz?",
            "tippi://schnellnotiz#x",
            "tippi://schnellnotiz/neu",
            "tippi://schnellnotiz/../einstellungen",
            "tippi://user@schnellnotiz",
            "tippi://user:pw@schnellnotiz",
            "tippi://schnellnotiz:8080"
        ] {
            XCTAssertNil(parse(string), string)
        }
    }

    func testRefusesOtherHostsAndSchemes() {
        for string in [
            "tippi://",
            "tippi:schnellnotiz",
            "tippi://einstellungen",
            "tippi://schnellnotizen",
            "tippi://diktat",
            "https://schnellnotiz",
            "tippiai://schnellnotiz",
            "file:///schnellnotiz"
        ] {
            XCTAssertNil(parse(string), string)
        }
    }
}
