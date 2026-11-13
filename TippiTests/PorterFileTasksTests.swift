import XCTest
@testable import Tippi

/// Datei-Aufgaben (2.38): Tippi liest Porters `Notizen.json` nur. Die Beispielliste unten ist
/// **Porters echte Ausgabe** (`JSONEncoder.notes` aus `Porter/Core/Notes.swift`, erzeugt
/// 2026-11-13), nicht nachgebaut – damit ein Formatfehler hier auffällt und nicht erst bei Michael.
final class PorterFileTasksTests: XCTestCase {
    private let home = "/Users/test"
    private var folder: URL!

    private let porterOutput = #"""
    {
      "notes" : {
        "/Volumes/Daten/Film.mov" : {
          "deleted" : false,
          "isDone" : false,
          "isTask" : true,
          "modified" : "2026-11-11T09:00:00Z",
          "text" : ""
        },
        "~/Coding" : {
          "deleted" : false,
          "isDone" : false,
          "isTask" : true,
          "modified" : "2026-11-13T08:30:00Z",
          "text" : "Ordner aufräumen"
        },
        "~/Desktop/Angebot.pdf" : {
          "deleted" : false,
          "isDone" : false,
          "isTask" : true,
          "modified" : "2026-11-12T10:00:00Z",
          "text" : "Angebot prüfen\nbis Freitag"
        },
        "~/Erledigt.txt" : {
          "deleted" : false,
          "isDone" : true,
          "isTask" : true,
          "modified" : "2023-11-14T22:13:20Z",
          "text" : "fertig"
        },
        "~/Nur Notiz.txt" : {
          "deleted" : false,
          "isDone" : false,
          "isTask" : false,
          "modified" : "2023-11-14T22:13:20Z",
          "text" : "Merkzettel"
        },
        "~/Weg.txt" : {
          "deleted" : true,
          "isDone" : false,
          "isTask" : false,
          "modified" : "2023-11-14T22:13:20Z",
          "text" : ""
        }
      },
      "version" : 1
    }
    """#

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "PorterFileTasksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Filter und Reihenfolge

    func testOnlyOpenTasksNewestFirst() throws {
        let tasks = try PorterFileTasks.openTasks(from: Data(porterOutput.utf8), home: home)
        XCTAssertEqual(tasks.map(\.key), ["~/Coding", "~/Desktop/Angebot.pdf", "/Volumes/Daten/Film.mov"])
    }

    func testFieldsAndPaths() throws {
        let tasks = try PorterFileTasks.openTasks(from: Data(porterOutput.utf8), home: home)
        let offer = try XCTUnwrap(tasks.first { $0.key == "~/Desktop/Angebot.pdf" })
        XCTAssertEqual(offer.url.path(percentEncoded: false), "/Users/test/Desktop/Angebot.pdf")
        XCTAssertEqual(offer.firstLine, "Angebot prüfen")
        XCTAssertEqual(offer.fileName, "Angebot.pdf")
        XCTAssertEqual(offer.modified, ISO8601DateFormatter().date(from: "2026-11-12T10:00:00Z"))
        let film = try XCTUnwrap(tasks.first { $0.key == "/Volumes/Daten/Film.mov" })
        XCTAssertEqual(film.firstLine, "")
        XCTAssertEqual(film.folderName, "/Volumes/Daten")
        XCTAssertEqual(offer.folderName, "~/Desktop")
        XCTAssertEqual(film.url.path(percentEncoded: false), "/Volumes/Daten/Film.mov")
    }

    func testKeyMappingMatchesPorter() {
        XCTAssertEqual(PorterFileTasks.url(for: "~", home: home)?.path(percentEncoded: false), "/Users/test")
        XCTAssertEqual(PorterFileTasks.url(for: "~/a b/c.txt", home: home + "/")?.path(percentEncoded: false), "/Users/test/a b/c.txt")
        XCTAssertEqual(PorterFileTasks.url(for: "/tmp/x", home: home)?.path(percentEncoded: false), "/tmp/x")
    }

    func testForeignKeysAreSkipped() {
        for key in ["relativ/datei.txt", "https://example.com/x", "file:///etc/passwd", "~andere/x", "", "/a\0b"] {
            XCTAssertNil(PorterFileTasks.url(for: key, home: home), key)
        }
        XCTAssertEqual(PorterFileTasks.url(for: "~/../../etc/x", home: home)?.isFileURL, true)
    }

    func testDoneTasksOnlyMeansEmpty() throws {
        let json = #"{"version":1,"notes":{"~/a":{"text":"x","isTask":true,"isDone":true,"modified":"2026-11-13T08:30:00Z","deleted":false}}}"#
        let file = folder.appending(path: "Notizen.json")
        try Data(json.utf8).write(to: file)
        XCTAssertEqual(PorterFileTasks.load(file: file, home: home), .empty)
    }

    // MARK: - Zustände beim Lesen

    func testMissingListIsQuietEmpty() {
        XCTAssertEqual(PorterFileTasks.load(file: folder.appending(path: "Notizen.json"), home: home), .empty)
    }

    func testICloudPlaceholderMeansLoading() throws {
        try Data().write(to: folder.appending(path: ".Notizen.json.icloud"))
        XCTAssertEqual(PorterFileTasks.load(file: folder.appending(path: "Notizen.json"), home: home), .loading)
    }

    func testValidListLoads() throws {
        let file = folder.appending(path: "Notizen.json")
        try Data(porterOutput.utf8).write(to: file)
        guard case .tasks(let tasks) = PorterFileTasks.load(file: file, home: home) else {
            return XCTFail("erwartet: Aufgaben")
        }
        XCTAssertEqual(tasks.count, 3)
    }

    func testBrokenListIsUnreadable() throws {
        let file = folder.appending(path: "Notizen.json")
        try Data("{ halb geschrieben".utf8).write(to: file)
        XCTAssertEqual(PorterFileTasks.load(file: file, home: home), .unreadable)
    }

    func testOversizedListIsUnreadable() throws {
        let file = folder.appending(path: "Notizen.json")
        try Data(count: PorterFileTasks.maxFileSize + 1).write(to: file)
        XCTAssertEqual(PorterFileTasks.load(file: file, home: home), .unreadable)
    }

    func testFolderInsteadOfFileIsUnreadable() throws {
        let file = folder.appending(path: "Notizen.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertEqual(PorterFileTasks.load(file: file, home: home), .unreadable)
    }

    /// Tippi schreibt nie in Porters Liste: Inhalt und Änderungsdatum bleiben nach dem Lesen gleich.
    func testLoadNeverWrites() throws {
        let file = folder.appending(path: "Notizen.json")
        try Data(porterOutput.utf8).write(to: file)
        let before = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.modificationDate] as? Date
        _ = PorterFileTasks.load(file: file, home: home)
        let after = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.modificationDate] as? Date
        XCTAssertEqual(before, after)
        XCTAssertEqual(try Data(contentsOf: file), Data(porterOutput.utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)), ["Notizen.json"])
    }
}
