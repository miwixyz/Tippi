import AppKit
import XCTest
@testable import Tippi

final class AuditFollowupTests: XCTestCase {
    func testExplicitReplacementTargetNeverFallsThroughToAnotherApp() {
        XCTAssertFalse(TextInsertion.isExpectedFrontmost(targetPID: 101, frontmostPID: 202))
        XCTAssertTrue(TextInsertion.isExpectedFrontmost(targetPID: 101, frontmostPID: 101))
        XCTAssertTrue(TextInsertion.isExpectedFrontmost(targetPID: nil, frontmostPID: 202))
    }

    func testAccessibilityFallbackStopsAtDeadlineAndDepthLimit() {
        XCTAssertTrue(TextInsertion.shouldContinueAXWalk(depth: 4, now: 1, deadline: 2))
        XCTAssertFalse(TextInsertion.shouldContinueAXWalk(depth: 15, now: 1, deadline: 2))
        XCTAssertFalse(TextInsertion.shouldContinueAXWalk(depth: 4, now: 2, deadline: 2))
    }

    func testOpenAIStreamRequiresAnExplicitEndAfterReceivingText() throws {
        var completion = OpenAIStreamCompletion()
        completion.observe(.delta("partial", truncated: false))
        XCTAssertThrowsError(try completion.validate())
        completion.observe(.done)
        XCTAssertNoThrow(try completion.validate())
    }

    func testOpenAIStopReasonCompletesWithoutDoneMarker() throws {
        let line = #"data: {"choices":[{"delta":{"content":"tail"},"finish_reason":"stop"}]}"#
        let event = try XCTUnwrap(OpenAIStreamLine.parse(line))
        XCTAssertEqual(event, .finished("tail"))
        var completion = OpenAIStreamCompletion()
        completion.observe(event)
        XCTAssertNoThrow(try completion.validate())
    }

    func testOpenAITruncationIsRejectedEvenIfDoneMarkerArrives() {
        var completion = OpenAIStreamCompletion()
        completion.observe(.delta("partial", truncated: true))
        completion.observe(.done)
        XCTAssertThrowsError(try completion.validate())
    }

    func testClipboardRestoreDoesNotOverwriteANewerCopy() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        var snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("Tippi result", forType: .string)
        snapshot.markOwnedChange(on: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("new user copy", forType: .string)
        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "new user copy")
    }

    func testClipboardRestoreRecoversTheOriginalWhenStillOwned() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        var snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("Tippi result", forType: .string)
        snapshot.markOwnedChange(on: pasteboard)
        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testCorruptHistoryDatabaseDoesNotCrashStoreInitialization() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let database = dir.appendingPathComponent("history.db")
        try Data("not a sqlite database".utf8).write(to: database)

        let store = HistoryStore(databaseURL: database)
        XCTAssertThrowsError(try store.count())
    }

    func testOfflineNoteConflictKeepsBothContentsInCloud() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let name = "Title — \(id.uuidString).txt"
        try "cloud edit".write(to: cloud.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try "offline edit".write(to: local.appendingPathComponent(name), atomically: true, encoding: .utf8)

        NotesStore.migrateLocalNotesIfNeeded(from: local, into: cloud)
        let files = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(try files.map { try String(contentsOf: $0, encoding: .utf8) }),
                       Set(["cloud edit", "offline edit"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent(name).path))
    }

    func testMigrationFindsSameNoteEvenAfterTitleChanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        try "cloud edit".write(to: cloud.appendingPathComponent("Cloud title — \(id.uuidString).txt"),
                               atomically: true, encoding: .utf8)
        try "offline edit".write(to: local.appendingPathComponent("Local title — \(id.uuidString).txt"),
                                 atomically: true, encoding: .utf8)

        NotesStore.migrateLocalNotesIfNeeded(from: local, into: cloud)
        let files = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(try files.map { try String(contentsOf: $0, encoding: .utf8) }),
                       Set(["cloud edit", "offline edit"]))
    }

    func testIdenticalOfflineNoteDoesNotCreateAConflictCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let name = "Title — \(UUID().uuidString).txt"
        try "same text".write(to: cloud.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try "same text".write(to: local.appendingPathComponent(name), atomically: true, encoding: .utf8)
        NotesStore.migrateLocalNotesIfNeeded(from: local, into: cloud)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cloud.path).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent(name).path))
    }

    func testEvictedCloudNoteKeepsOfflineTextAsSeparateConflictCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = root.appendingPathComponent("local")
        let cloud = root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let name = "Title — \(UUID().uuidString).txt"
        try "offline edit".write(to: local.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try Data().write(to: cloud.appendingPathComponent(".\(name).icloud"))
        NotesStore.migrateLocalNotesIfNeeded(from: local, into: cloud)

        let cloudNotes = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertEqual(cloudNotes.count, 1)
        XCTAssertEqual(try String(contentsOf: cloudNotes[0], encoding: .utf8), "offline edit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appendingPathComponent(".\(name).icloud").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent(name).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.appendingPathComponent(name).path))
    }

    func testStorageSwitchUsesCloudOriginalRatherThanNewerOfflineModel() {
        let id = UUID()
        let cloud = Note(id: id, content: "cloud edit", createdAt: .distantPast, modifiedAt: .distantPast)
        let local = Note(id: id, content: "offline edit", createdAt: .distantPast, modifiedAt: .distantFuture)
        let oldDirectory = URL(fileURLWithPath: "/tmp/tippi-local")
        let newDirectory = URL(fileURLWithPath: "/tmp/tippi-cloud")
        let mergeCurrent = NotesStore.currentNotesForRefresh(
            [local], from: oldDirectory, to: newDirectory, mutatedIDs: []
        )
        let result = NotesStore.preferNewer(loaded: [cloud], current: mergeCurrent)
        XCTAssertEqual(result.first?.content, "cloud edit")
    }

    @MainActor
    func testDeleteFollowsAllQueuedSaves() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = NotesStore(directory: dir, refreshOnInit: false)
        let created = store.create()
        for n in 0..<12 {
            var edited = created
            edited.content = "revision \(n)\n" + String(repeating: "x", count: 20_000)
            store.save(edited)
        }
        store.delete(created)
        await store.waitForPendingOperations()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files.contains { $0.hasSuffix("\(created.id.uuidString).txt") })
    }

    func testRefreshPreservesANoteCreatedWhileDiskWasLoading() {
        let new = Note(content: "just created")
        let result = NotesStore.preferNewer(loaded: [], current: [new], preservingIDs: [new.id])
        XCTAssertEqual(result, [new])
    }

    func testRefreshDoesNotResurrectANoteDeletedWhileDiskWasLoading() {
        let deleted = Note(content: "just deleted")
        let result = NotesStore.preferNewer(loaded: [deleted], current: [], deletedIDs: [deleted.id])
        XCTAssertTrue(result.isEmpty)
    }
}
