import XCTest
@testable import Tippi

/// Measures whether `ThrowawayDefaults.removeAll()` actually removes the suite,
/// rather than assuming it from the API names.
///
/// Built 2026-09-20 after three hypotheses in a row were refuted by the same
/// number: a full test run left exactly 35 preference domains behind before and
/// after two different "fixes". At that point the missing thing is not another
/// idea, it is a measurement inside the process — from the outside, "cleanup
/// ran and something recreated the file" and "cleanup never worked" look
/// identical.
final class ThrowawayDefaultsTests: XCTestCase {

    private func plistURL(for name: String) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(name).plist")
    }

    /// The direct question: after `removeAll()`, is the plist gone *right now*,
    /// inside the same process?
    func testRemoveAllDeletesThePlistImmediately() throws {
        let suites = ThrowawayDefaults()
        let defaults = suites.make(prefix: "TippiTests.selfcheck")
        defaults.set("x", forKey: "probe")
        // Force the write, otherwise the file may not exist yet and the test
        // would pass without having measured anything.
        defaults.synchronize()

        let name = try XCTUnwrap(suites.debugNames.first)
        let url = plistURL(for: name)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "Precondition failed: the suite never reached disk, so this test cannot measure removal."
        )

        suites.removeAll()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            """
            removeAll() left \(url.lastPathComponent) on disk. Cleanup itself is \
            the problem — not a later flush by cfprefsd.
            """
        )
    }

    /// Values must be gone even if the file lingers, so a leftover shell can
    /// never carry state into the next run.
    func testRemoveAllClearsTheValues() throws {
        let suites = ThrowawayDefaults()
        let defaults = suites.make(prefix: "TippiTests.selfcheck")
        defaults.set("secret", forKey: "probe")
        defaults.synchronize()
        let name = try XCTUnwrap(suites.debugNames.first)

        suites.removeAll()

        XCTAssertNil(
            UserDefaults(suiteName: name)?.string(forKey: "probe"),
            "A value survived removeAll() — a later test could read it."
        )
        // Re-created the suite by asking for it above; clean that up too so this
        // test does not become the thing it measures.
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: plistURL(for: name))
    }

    func testRemoveAllIsIdempotent() {
        let suites = ThrowawayDefaults()
        _ = suites.make(prefix: "TippiTests.selfcheck")
        suites.removeAll()
        suites.removeAll()   // must not crash or resurrect anything
        XCTAssertTrue(suites.debugNames.isEmpty)
    }
}
