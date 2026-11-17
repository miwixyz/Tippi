import CryptoKit
import XCTest
@testable import Tippi

/// Audit 2026-11-17, Niedrig-Liste: Funde 6, 9, 10, 17.
final class AuditNiedrigTests: XCTestCase {

    // MARK: Fund 6 — noch ladende Notiz gilt nicht als gelöscht

    func testStillDownloadingNoteIsReportedPending() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let loadedID = UUID(), placeholderID = UUID()
        try "Da\nText".write(to: dir.appendingPathComponent("Da — \(loadedID.uuidString).txt"), atomically: true, encoding: .utf8)
        // iCloud-Platzhalter einer Notiz, deren Datei noch nicht geladen ist.
        try Data().write(to: dir.appendingPathComponent(".Unterwegs — \(placeholderID.uuidString).txt.icloud"))

        let result = NotesStore.loadAllNotesAndPending(from: dir)
        XCTAssertEqual(result.notes.map(\.id), [loadedID])
        XCTAssertEqual(result.pending, [placeholderID])
    }

    func testRefreshKeepsANotePendingOnDisk() {
        let open = Note(content: "offen\nText")
        let result = NotesStore.preferNewer(loaded: [], current: [open], preservingIDs: [open.id])
        XCTAssertEqual(result, [open], "noch ladend ≠ gelöscht")
    }

    // MARK: Fund 9 — Anbieter-Session

    func testProviderSessionRefusesRedirects() async {
        let delegate = RefuseProviderRedirects()
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1")!, statusCode: 302,
                                       httpVersion: nil, headerFields: ["Location": "https://evil.example/"])!
        let task = URLSession.shared.dataTask(with: URL(string: "https://api.example.com/v1")!)
        let next = await delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                                             newRequest: URLRequest(url: URL(string: "https://evil.example/")!))
        XCTAssertNil(next, "Schlüssel-Header dürfen keinem Redirect folgen")
        XCTAssertNil(ProviderSession.shared.configuration.httpCookieStorage)
        XCTAssertNil(ProviderSession.shared.configuration.urlCache)
    }

    func testOversizedProviderAnswerIsRejected() {
        XCTAssertNoThrow(try ProviderSession.checkSize(ProviderSession.maxResponseBytes))
        XCTAssertThrowsError(try ProviderSession.checkSize(ProviderSession.maxResponseBytes + 1))
    }

    // MARK: Fund 10 — Whisper-Modelle mit Prüfsumme

    func testWhisperModelsArePinnedAndChecksummed() {
        for model in WhisperModel.catalog {
            XCTAssertTrue(model.downloadURL.absoluteString.contains("/resolve/\(WhisperModel.revision)/"),
                          "\(model.id): feste Fassung statt main")
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertNotNil(model.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
        }
        XCTAssertEqual(Set(WhisperModel.catalog.map(\.sha256)).count, WhisperModel.catalog.count)
    }

    func testChecksumOfAFileMatchesCryptoKit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tippi-sha-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data((0..<(5 * 1024 * 1024)).map { UInt8($0 % 251) })   // über ein Stück von 4 MB hinaus
        try data.write(to: url)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(WhisperModel.sha256Hex(of: url), expected)
    }

    // MARK: Fund 17 — Transkript-Rest nach Absturz

    func testOrphanSweepIncludesTheTranscriptSidecar() {
        XCTAssertTrue(AudioRecorder.isOrphanedRecording("tippi-voice-1234.wav"))
        XCTAssertTrue(AudioRecorder.isOrphanedRecording("tippi-voice-1234.wav.txt"))
        XCTAssertFalse(AudioRecorder.isOrphanedRecording("tippi-model-1234.tmp"))
        XCTAssertFalse(AudioRecorder.isOrphanedRecording("notiz.wav.txt"))
    }
}
