#if DEBUG
import AppKit
import Foundation

/// Selbsttest der Bild-Testkopie (Muster aus Gnotchi, BAMA `test-mac-app`; Tippi 2026-11-16): ruft im laufenden
/// Bündel dieselben Teile auf wie die Oberfläche und meldet je Schritt PASS oder FAIL. Kommt als Befehl `selftest`
/// über den Befehlskanal (`tippictl selftest`, Exit 0/1) – Tippi ist eine Ein-Instanz-Menüleisten-App.
///
/// Abgeschottet wie die ganze Kopie (B3–B5): eigener Datenordner, Notizen nur in einem Wegwerf-Ordner darin,
/// keine Einstellungen, kein Schlüsselbund (Verlauf und Snippets bleiben deshalb draußen), kein Netz, keine
/// Hotkeys, kein Mikrofon, kein Bedienungshilfen-Zugriff.
@MainActor
enum SelfTest {
    struct Step {
        let name: String
        let ok: Bool
        let detail: String
    }

    static func run(windowFor: (String) -> NSWindow?) async -> [Step] {
        var steps: [Step] = []
        steps.append(isolation())
        steps.append(resources())
        steps.append(bundleSeal())
        steps.append(registries())
        steps.append(await emoji())
        steps.append(contentsOf: await windows(windowFor))
        steps.append(await notesSmoke())
        return steps
    }

    /// Antwort für `Antworten/<id>.json`: `bestanden` plus `schritte`. Ohne Schritte gilt es nicht als bestanden.
    static func answer(_ steps: [Step]) -> [String: Any] {
        ["ok": true,
         "bestanden": !steps.isEmpty && steps.allSatisfy(\.ok),
         "schritte": steps.map { ["name": $0.name, "ok": $0.ok, "detail": $0.detail] as [String: Any] }]
    }

    // MARK: Schritte

    /// Die Kopie darf nie auf Michaels echte Daten zeigen.
    private static func isolation() -> Step {
        let id = Bundle.main.bundleIdentifier ?? "?"
        let support = BildKopie.applicationSupport.path
        let ok = id == "dev.mwlr.tippi.bild" && BildKopie.isActive && support.hasSuffix("Tippi Bild/Daten")
        return Step(name: "Abschottung", ok: ok, detail: "Kennung \(id), Daten unter …/" + (support.components(separatedBy: "/").suffix(2).joined(separator: "/")))
    }

    /// Schrift, beide Sprachen und Wörterbuch-Texte im Bündel – fehlt etwas, fällt die Oberfläche still zurück.
    private static func resources() -> Step {
        let font = NSFontManager.shared.availableFontFamilies.contains("Plus Jakarta Sans")
        let locales = Set(Bundle.main.localizations)
        let missingLocales = ["en", "de"].filter { !locales.contains($0) }
        let key = "settings.window.title"
        let translated = String(localized: String.LocalizationValue(key)) != key
        let ok = font && missingLocales.isEmpty && translated
        let fontText = font ? "da" : "FEHLT"
        let localeText = missingLocales.isEmpty ? "en+de" : "fehlt: " + missingLocales.joined(separator: ", ")
        return Step(name: "Ressourcen", ok: ok,
                    detail: "Schrift " + fontText + ", Sprachen " + localeText + ", Texte " + (translated ? "übersetzt" : "ohne Übersetzung"))
    }

    /// Siegel unversehrt (die Kopie trägt eine andere Kennung als das echte Tippi, deshalb ohne Team-Anforderung).
    private static func bundleSeal() -> Step {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code)
        if status == errSecSuccess, let code {
            let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures)
            status = SecStaticCodeCheckValidity(code, flags, nil)
        }
        return Step(name: "Bundle-Siegel", ok: status == errSecSuccess, detail: "OSStatus \(status)")
    }

    /// Anbieter und eingebaute Prompts: eindeutige, nicht leere Kennungen (Doppelte überschrieben sich still im Picker).
    private static func registries() -> Step {
        let providerIDs = LLMRouter.allProviders.map(\.id)
        let promptIDs = DemoPrompt.builtIn.map(\.id)
        let providersOK = !providerIDs.isEmpty && Set(providerIDs).count == providerIDs.count && !providerIDs.contains("")
        let promptsOK = !promptIDs.isEmpty && Set(promptIDs).count == promptIDs.count
        return Step(name: "Anbieter und Prompts", ok: providersOK && promptsOK,
                    detail: "\(providerIDs.count) Anbieter, \(promptIDs.count) eingebaute Prompts, Kennungen eindeutig: " + (providersOK && promptsOK ? "ja" : "NEIN"))
    }

    /// Emoji-Wörterbuch lädt aus dem Bündel (Hintergrund-Dekodierung) und findet etwas.
    private static func emoji() async -> Step {
        let db = EmojiDatabase.shared
        db.load()
        for _ in 0..<50 where !db.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
        let hits = db.isLoaded ? db.search("smile", limit: 5).count : 0
        return Step(name: "Emoji-Wörterbuch", ok: db.isLoaded && db.all.count > 1000 && hits > 0,
                    detail: db.isLoaded ? "\(db.all.count) Emoji, Suche „smile“: \(hits) Treffer" : "nicht geladen nach 5 s")
    }

    /// Einstellungen, schlanker Reiter Hilfe und Über öffnen sich wirklich (sichtbar mit ihrer Kennung). Danach zu.
    private static func windows(_ windowFor: (String) -> NSWindow?) async -> [Step] {
        var result: [Step] = []
        for id in [DebugCommand.settingsWindow, DebugCommand.helpWindow, DebugCommand.aboutWindow] {
            guard let win = windowFor(id) else {
                result.append(Step(name: "Fenster \(id)", ok: false, detail: "nicht erlaubt/gebaut"))
                continue
            }
            win.makeKeyAndOrderFront(nil)
            for _ in 0..<15 where !win.isVisible { try? await Task.sleep(for: .milliseconds(100)) }
            result.append(Step(name: "Fenster \(id)", ok: win.isVisible,
                               detail: "\(Int(win.frame.width))×\(Int(win.frame.height))"))
            win.close()
        }
        return result
    }

    /// Rauchtest der Notizen: viele Speicherungen kurz hintereinander (Schreibwarteschlange abseits des Hauptthreads),
    /// dann Inhalt auf der Platte prüfen, löschen, Ordner wieder entfernen. Nur im Wegwerf-Ordner der Kopie.
    private static func notesSmoke() async -> Step {
        let dir = BildKopie.applicationSupport.appendingPathComponent("Selbsttest-" + UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            return Step(name: "Notizen-Rauchtest", ok: false, detail: "Ordner nicht angelegt: \(error.localizedDescription)")
        }
        defer { try? fm.removeItem(at: dir) }
        let store = NotesStore(directory: dir, refreshOnInit: false)
        var note = store.create()
        let rounds = 25
        for i in 1...rounds {
            note.content = "Selbsttest \(i)"
            store.save(note)
            try? await Task.sleep(for: .milliseconds(40))
        }
        try? await Task.sleep(for: .milliseconds(800))
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "txt" } ?? []
        let text = files.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let written = files.count == 1 && text.contains("Selbsttest \(rounds)")
        store.delete(note)
        try? await Task.sleep(for: .milliseconds(800))
        let left = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "txt" } ?? []).count
        return Step(name: "Notizen-Rauchtest", ok: written && left == 0,
                    detail: "\(rounds) Speicherungen, auf Platte: \(files.count) Datei" + (written ? " mit letztem Stand" : " MIT FALSCHEM STAND")
                        + ", nach Löschen übrig: \(left)")
    }
}
#endif
