import XCTest
@testable import Tippi

/// 2026-11-20: iCloud Drive ohne Mobilfunk am iPhone, Änderungen lagen zwei Tage nur dort.
/// Tippi zählt hängende Uploads wie TippAI, frisch gespeicherte nicht.
final class PendingUploadTests: XCTestCase {

    private var dir: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["alt", "frisch", "hochgeladen", "lokal"] {
            try "x".write(to: dir.appendingPathComponent("\(name) — \(UUID().uuidString).txt"), atomically: true, encoding: .utf8)
        }
        try "{}".write(to: dir.appendingPathComponent(".tippai-authorship.json"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testCountsOnlyStaleNotUploadedNotes() {
        let count = NotesStore.pendingUploadCount(in: dir, now: now) { url in
            let name = url.lastPathComponent
            if name.hasPrefix("alt") { return (false, self.now.addingTimeInterval(-3600)) }
            if name.hasPrefix("frisch") { return (false, self.now.addingTimeInterval(-5)) }
            if name.hasPrefix("hochgeladen") { return (true, self.now.addingTimeInterval(-3600)) }
            return (nil, self.now.addingTimeInterval(-3600)) // nicht in iCloud
        }
        XCTAssertEqual(count, 1)
    }

    func testLocalFolderNeverCountsAsPending() {
        XCTAssertEqual(NotesStore.pendingUploadCount(in: dir, now: now), 0)
    }

    func testMissingFolderCountsZero() {
        XCTAssertEqual(NotesStore.pendingUploadCount(in: dir.appendingPathComponent("fehlt"), now: now), 0)
    }
}
