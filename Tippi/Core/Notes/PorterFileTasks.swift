import AppKit
import Foundation

/// „Datei-Aufgaben“ (2.38): offene Aufgaben, die in Porter an Dateien und Ordnern hängen.
///
/// Tippi **liest nur** Porters Liste `iCloud Drive/Porter/Notizen.json` und schreibt nie hinein
/// (Michael, 12.11., Porter-Chat-Übergabe „Notizen an Dateien/Ordnern entschieden“). Das Format ist
/// Porters `NoteBook`/`FileNote` (`~/Coding/Porter/Porter/Core/Notes.swift`): `version`, `notes` als
/// Wörterbuch Pfad → Notiz, Pfade mit `~` für das Benutzerverzeichnis, Daten als ISO 8601.
/// Sicherheitsentwurf: `docs/SECURE-DESIGN-datei-aufgaben.md`.
enum PorterFileTasks {
    static let porterBundleID = "dev.mwlr.porter"
    /// Porters Liste ist ein paar KB groß; alles weit darüber ist nicht Porters Datei.
    static let maxFileSize = 5 * 1024 * 1024

    static var standardFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Porter/Notizen.json")
    }

    /// Eine Notiz aus Porters Liste. Nur lesen: Felder wie bei Porters `FileNote`.
    struct Entry: Decodable, Equatable {
        var text: String
        var isTask: Bool
        var isDone: Bool
        var modified: Date
        var deleted: Bool

        var isOpenTask: Bool { isTask && !isDone && !deleted }
    }

    struct Book: Decodable {
        var version: Int
        var notes: [String: Entry]
    }

    /// Eine offene Aufgabe, wie Tippi sie zeigt.
    struct Item: Identifiable, Equatable {
        /// Porters Schlüssel (Pfad mit `~`).
        let key: String
        let url: URL
        let text: String
        let modified: Date

        var id: String { key }
        var fileName: String { url.lastPathComponent.isEmpty ? key : url.lastPathComponent }
        /// Ordner, in dem die Datei liegt, in Porters Schreibweise (`~/Desktop`) – Unterzeile, wenn die Aufgabe
        /// keinen Text hat und der Dateiname schon die Hauptzeile ist.
        var folderName: String {
            guard let slash = key.lastIndex(of: "/"), slash != key.startIndex else { return key == "~" ? "~" : "/" }
            return String(key[..<slash])
        }

        /// Erste nicht leere Zeile – wie Porters `firstLine`.
        var firstLine: String {
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        }
    }

    enum State: Equatable {
        /// Liste fehlt oder enthält keine offene Aufgabe – ruhiger Leer-Zustand, kein Fehler.
        case empty
        /// Liste liegt nur als iCloud-Platzhalter vor; das Laden ist angestoßen.
        case loading
        /// Liste vorhanden, aber nicht lesbar. Tippi zeigt eine ruhige Zeile, Porter bleibt zuständig.
        case unreadable
        case tasks([Item])
    }

    // MARK: - Lesen

    /// Offene Aufgaben aus den Rohdaten, neueste Änderung zuerst. Rein, damit testbar.
    static func openTasks(from data: Data, home: String = NSHomeDirectory()) throws -> [Item] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let book = try decoder.decode(Book.self, from: data)
        return book.notes.compactMap { key, entry -> Item? in
            guard entry.isOpenTask, let url = url(for: key, home: home) else { return nil }
            return Item(key: key, url: url, text: entry.text, modified: entry.modified)
        }
        .sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.key < $1.key }
    }

    /// Porters Schlüssel → Datei-URL. Nur `~`, `~/…` und absolute Pfade; alles andere ist nicht
    /// Porters Format und wird übergangen (keine relativen Pfade, keine Adressen mit Schema).
    static func url(for key: String, home: String = NSHomeDirectory()) -> URL? {
        let path: String
        if key == "~" {
            path = home
        } else if key.hasPrefix("~/") {
            path = (home.hasSuffix("/") ? String(home.dropLast()) : home) + key.dropFirst()
        } else if key.hasPrefix("/") {
            path = key
        } else {
            return nil
        }
        guard !path.contains("\0") else { return nil }
        return URL(filePath: path).standardizedFileURL
    }

    /// Liest die Liste. Wirft nie: jeder Ausgang ist ein Zustand für die Oberfläche.
    static func load(file: URL = standardFile, home: String = NSHomeDirectory()) -> State {
        let manager = FileManager.default
        let path = file.path(percentEncoded: false)
        guard manager.fileExists(atPath: path) else {
            let placeholder = file.deletingLastPathComponent().appending(path: "." + file.lastPathComponent + ".icloud")
            if manager.fileExists(atPath: placeholder.path(percentEncoded: false)) {
                // Laden anstoßen ändert die Liste nicht; Tippi schreibt weiterhin nichts hinein.
                try? manager.startDownloadingUbiquitousItem(at: file)
                return .loading
            }
            return .empty
        }
        let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .fileSizeKey, .isRegularFileKey])
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? manager.startDownloadingUbiquitousItem(at: file)
            return .loading
        }
        guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= maxFileSize else { return .unreadable }

        // Koordiniert lesen wie Porter, damit kein halb geschriebener Stand ankommt.
        var data: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            data = try? Data(contentsOf: url)
        }
        guard coordinationError == nil, let data, data.count <= maxFileSize,
              let tasks = try? openTasks(from: data, home: home) else { return .unreadable }
        return tasks.isEmpty ? .empty : .tasks(tasks)
    }

    // MARK: - Öffnen

    /// Porter.app, falls installiert. Ein **laufendes** Porter zuerst: `open(…withApplicationAt:)` mit einem anderen
    /// Pfad startete sonst ein zweites Porter (gemessen 13.11., Debug-Porter lief, `/Applications`-Porter kam dazu).
    /// Danach `/Applications`, damit kein alter Build-Ordner gewinnt.
    static func porterApp(workspace: NSWorkspace = .shared) -> URL? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: porterBundleID)
            .first(where: { !$0.isTerminated })?.bundleURL {
            return running
        }
        for folder in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let candidate = URL(filePath: folder).appending(path: "Porter.app")
            if Bundle(url: candidate)?.bundleIdentifier == porterBundleID { return candidate }
        }
        return workspace.urlForApplication(withBundleIdentifier: porterBundleID)
    }

    /// Bereich zeigen? Nur wer Porter nutzt, soll ihn sehen: Porter installiert oder Liste vorhanden.
    static func isRelevant(file: URL = standardFile) -> Bool {
        porterApp() != nil || FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// Klick auf eine Aufgabe: Datei in Porter öffnen; ohne Porter im Finder zeigen.
    /// Nie mit dem Standardprogramm der Datei öffnen – die Liste kommt über iCloud, ein Eintrag
    /// könnte auf ein Programm zeigen.
    static func open(_ task: Item, workspace: NSWorkspace = .shared) {
        guard let porter = porterApp(workspace: workspace) else {
            workspace.activateFileViewerSelecting([task.url])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([task.url], withApplicationAt: porter, configuration: configuration) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async { workspace.activateFileViewerSelecting([task.url]) }
        }
    }
}
