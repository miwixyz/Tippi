import XCTest
@testable import Tippi

/// Only tests `parseFavoriteIDs` — the pure, dependency-free part of
/// `NotesPreferences`. Everything else in that type reads/writes the real
/// `NSUbiquitousKeyValueStore.default`, which needs an iCloud-entitled,
/// signed app host to behave meaningfully; not worth the flakiness of
/// exercising it from a unit test.
final class NotesPreferencesTests: XCTestCase {
    func testParseFavoriteIDsRoundTripsValidUUIDs() {
        let id1 = UUID()
        let id2 = UUID()
        let parsed = NotesPreferences.parseFavoriteIDs(from: [id1.uuidString, id2.uuidString])
        XCTAssertEqual(parsed, [id1, id2])
    }

    /// A value that was never a real UUID — e.g. synced from some future,
    /// incompatible version of the app — must be dropped, not crash.
    func testParseFavoriteIDsDropsMalformedEntries() {
        let id = UUID()
        let parsed = NotesPreferences.parseFavoriteIDs(from: [id.uuidString, "not-a-uuid", ""])
        XCTAssertEqual(parsed, [id])
    }

    func testParseFavoriteIDsEmptyInputIsEmptySet() {
        XCTAssertTrue(NotesPreferences.parseFavoriteIDs(from: []).isEmpty)
    }
}
