// Messwerkzeug: Taugt Apple Intelligence für Tippis Diktat-Bereinigung und die
// eingebauten Prompts? Schickt echte Tippi-Prompts an das Modell auf dem Mac.
//
// Die Prompts werden LIVE aus dem Code gelesen (geprüft wird, was ausgeliefert wird):
//   - Diktat-Bereinigung: DictationSettings.defaultPostProcessPrompt
//     (Tippi/Core/DictationController.swift), Temperatur-Hinweis 0.1 wie in der App
//   - Improve / Defuse / Add emojis / Lengthen: DemoPrompt.swift, mit der
//     Rollen-Präambel davor, {language} → "German", ohne Temperatur-Hinweis
// Die Anfrage selbst läuft über Tippi/LLM/AppleIntelligenceModel.swift — dieselbe Datei,
// die in der App steckt, hier nur mit eingebaut.
//
// Aufruf (aus dem Repo-Wurzelordner):
//   xcrun swiftc -O -o /tmp/tippi-ai-messung \
//     scripts/apple-intelligence-messung/main.swift Tippi/LLM/AppleIntelligenceModel.swift \
//     && /tmp/tippi-ai-messung
//   /tmp/tippi-ai-messung --nur bereinigung     # nur eine Gruppe (bereinigung|improve|defuse|emojis|grenze)
//   /tmp/tippi-ai-messung --voll                # zusätzlich die vollen Antworten
//
// Einschränkung: Ein Kommandozeilen-Programm ist nicht die App. Antwortqualität und
// Ablehnungen sind dieselben (gleiches Modell, gleicher Code); die Zeiten in der App
// können abweichen, vor allem bei der ersten Anfrage nach langer Pause.
//
// Exit: 0 = gelaufen · 2 = Aufbaufehler (Prompt im Code nicht gefunden, Modell nicht verfügbar)

import Foundation
import FoundationModels

// MARK: - Prompts aus dem Code

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(2)
}

/// Inhalt des ersten mehrzeiligen Swift-Strings nach `marker` — mit Swifts Einrückungsregel.
func swiftString(in source: String, after marker: String, file: String) -> String {
    guard let markerRange = source.range(of: marker) else { fail("„\(marker)“ nicht in \(file)") }
    guard let open = source.range(of: "\"\"\"", range: markerRange.upperBound..<source.endIndex),
          let close = source.range(of: "\"\"\"", range: open.upperBound..<source.endIndex)
    else { fail("Kein mehrzeiliger String nach „\(marker)“ in \(file)") }
    var lines = source[open.upperBound..<close.lowerBound].components(separatedBy: "\n")
    lines.removeFirst()                                   // Rest der Zeile mit """
    let closingLine = lines.removeLast()                  // Einrückung des schließenden """
    let indent = closingLine.prefix { $0 == " " }.count
    let body = lines.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " }.count))) }
        .joined(separator: "\n")
    if body.contains("\\(") { fail("Interpolation im Prompt nach „\(marker)“ — Messwerkzeug anpassen") }
    return body.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
}

let root = FileManager.default.currentDirectoryPath
func read(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: root + "/" + path, encoding: .utf8) else {
        fail("\(path) nicht lesbar — aus dem Repo-Wurzelordner starten")
    }
    return text
}

let dictationFile = "Tippi/Core/DictationController.swift"
let demoFile = "Tippi/UI/PromptPopup/DemoPrompt.swift"
let dictationSource = read(dictationFile)
let demoSource = read(demoFile)

let cleanupPrompt = swiftString(in: dictationSource, after: "static let defaultPostProcessPrompt", file: dictationFile)
let roleBoundary = swiftString(in: demoSource, after: "static let roleBoundary", file: demoFile)
func demoPrompt(_ id: String) -> String {
    guard let idRange = demoSource.range(of: "id: \"\(id)\"") else { fail("Prompt „\(id)“ nicht in \(demoFile)") }
    let rest = String(demoSource[idRange.upperBound...])
    let raw = swiftString(in: rest, after: "systemPrompt:", file: demoFile)
    return roleBoundary + "\n\n" + raw.replacingOccurrences(of: "{language}", with: "German")
}
let minChars: Int = {
    guard let line = dictationSource.components(separatedBy: "\n").first(where: { $0.contains("static let postProcessMinChars") }),
          let value = Int(line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
    else { fail("postProcessMinChars nicht in \(dictationFile)") }
    return value
}()

// MARK: - Fälle

struct Case {
    let group: String
    let label: String
    let instructions: String
    let hint: Double?           // wie die App: 0.1 nur für die Diktat-Bereinigung
    let text: String
    var mustNotContain: [String] = []   // Kleinbuchstaben; Treffer = beantwortet/falsch
}

let cleanup = { (label: String, text: String, not: [String]) in
    Case(group: "bereinigung", label: label, instructions: cleanupPrompt, hint: 0.1, text: text, mustNotContain: not)
}
let demo = { (group: String, id: String, label: String, text: String, not: [String]) in
    Case(group: group, label: label, instructions: demoPrompt(id), hint: nil, text: text, mustNotContain: not)
}

/// Langer Text ohne Wiederholungen — sonst „verbessert“ das Modell ihn legitim durch Weglassen.
/// Für die Grenzfälle mit „fixGrammar“: der Prompt verlangt jedes Wort zurück, die Antwort ist
/// also so lang wie die Eingabe.
func longText(paragraphs: Int) -> String {
    let towns = ["Augsburg", "Bremen", "Chemnitz", "Dresden", "Erfurt", "Freiburg", "Göttingen", "Hamburg", "Ingolstadt", "Jena"]
    let films = ["einen Western", "eine Komödie", "einen Krimi", "einen Zeichentrickfilm", "eine Doku", "ein Drama", "einen Thriller"]
    return (1...paragraphs).map { n in
        let town = towns[n % towns.count], film = films[n % films.count]
        return "Absatz \(n): Im Kino in \(town) läuft am \(n % 28 + 1). Tag des Monats um \(n % 12 + 10) Uhr \(film). " +
            "Die Kasse öffnet \(n % 50 + 10) Minuten vorher, Saal \(n % 9 + 1) hat \(n * 7 % 300 + 40) Plätze, " +
            "und für Gruppen ab \(n % 15 + 5) Personen gibt es \(n % 30 + 5) Prozent Rabatt auf Popcorn und Getränke."
    }.joined(separator: "\n\n")
}

var cases: [Case] = [
    cleanup("Füllwörter", "also ich wollte äh halt nur sagen dass das meeting morgen um zehn uhr ist und ähm wir brauchen noch die die präsentation", []),
    cleanup("Begrüßung kurz", "hallo wie gehts dir", ["mir geht", "danke", "gut,", "wie kann ich"]),
    cleanup("Begrüßung + Frage", "hallo wie gehts dir ich wollte fragen ob du morgen abend zeit hast für ein bier", ["mir geht", "ja,", "gerne", "wie kann ich", "leider"]),
    cleanup("Selbstkorrektur", "wir treffen uns am dienstag nein am mittwoch um drei im büro und dann äh gehen wir zusammen essen", ["dienstag"]),
    cleanup("Frage an die KI", "kannst du mir mal sagen wie spät es eigentlich gerade ist und ob ich noch den zug kriege", ["es ist ", "uhr", "ich kann", "leider"]),

    demo("improve", "improve", "Füllwörter", "Also ich wollte nur mal kurz fragen, ob wir das Treffen vielleicht eventuell auf nächste Woche verschieben könnten, weil ich diese Woche irgendwie echt total viel um die Ohren habe.", []),
    demo("improve", "improve", "Begrüßung", "hallo wie gehts dir", ["mir geht", "danke", "wie kann ich"]),
    demo("improve", "improve", "Kino-Info", "Die Kinokasse öffnet ab sofort schon um 17 Uhr, damit die Gäste mehr Zeit haben, sich Popcorn und Getränke zu holen, bevor der Film anfängt.", []),

    demo("defuse", "defuse", "Lieferung", "Das ist doch echt die größte Scheiße, ihr Idioten habt schon wieder die Lieferung verbockt! Seit drei Wochen warte ich auf das verdammte Paket und keiner von euch Vollpfosten ruft zurück. Wenn das bis Freitag nicht da ist, könnt ihr euch euren Laden sonst wohin stecken.", ["scheiße", "idioten", "vollpfosten", "verdammt"]),
    demo("defuse", "defuse", "Nachbarn", "Mir reicht's jetzt mit eurem Scheiß-Lärm jede Nacht bis zwei Uhr! Ihr asozialen Penner habt null Respekt. Nächstes Mal ruf ich die Bullen, und dann ist Schluss mit lustig.", ["scheiß", "penner", "asozial", "bullen"]),
    demo("defuse", "defuse", "Kollege", "Ehrlich, Thomas, du bist so ein unfähiger Idiot. Zum dritten Mal hast du meine Folien kaputtgemacht und tust dann so, als wärst du unschuldig. Ich hab die Schnauze voll von dir.", ["idiot", "unfähig", "schnauze"]),

    demo("emojis", "addEmojis", "Kino-Post", "Heute Abend zeigen wir die Premiere von Dune 3. Popcorn gibt es zum halben Preis. Wir freuen uns auf euch!", []),
    demo("emojis", "addEmojis", "Krankmeldung", "Ich bin morgen leider krank und kann nicht ins Büro kommen. Ich melde mich, sobald es mir besser geht.", []),
    demo("emojis", "addEmojis", "Einladung", "Geburtstagsfeier am Samstag im Garten, bring gute Laune und einen Salat mit.", []),

    // Grenzfälle: Kontextfenster. Erwartet: Fehler „zu lang“ — nie ein halber Text.
    demo("grenze", "fixGrammar", "Eingabe zu lang", longText(paragraphs: 160), []),
    demo("grenze", "fixGrammar", "Antwort sprengt Fenster", longText(paragraphs: 70), []),
]

let args = CommandLine.arguments
let showFull = args.contains("--voll")
if let i = args.firstIndex(of: "--nur"), i + 1 < args.count {
    cases = cases.filter { $0.group == args[i + 1] }
}

// MARK: - Lauf

if let reason = AppleIntelligenceModel.unavailableReason {
    fail("Apple Intelligence nicht verfügbar: \(reason)")
}

func short(_ text: String, _ max: Int = 120) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ⏎ ")
    return flat.count <= max ? flat : String(flat.prefix(max)) + "… (\(text.count) Z.)"
}

var fullOutputs: [String] = []

/// Token der Eingabe laut Modell (ab macOS 26.4) — zeigt, ob ein Grenzfall das Fenster wirklich sprengt.
func tokens(_ text: String) async -> String {
    if #available(macOS 26.4, *), let n = try? await SystemLanguageModel.default.tokenCount(for: text) {
        return "\(n) Token"
    }
    return "? Token"
}

func run(_ testCase: Case, guardrails: AppleIntelligenceModel.Guardrails) async -> String {
    let start = Date()
    var result: String
    var rejected = "nein"
    var check = ""
    do {
        let out = try await AppleIntelligenceModel.respond(
            instructions: testCase.instructions, text: testCase.text,
            sampling: AppleIntelligenceModel.sampling(forTemperatureHint: testCase.hint),
            guardrails: guardrails)
        result = short(out.trimmingCharacters(in: .whitespacesAndNewlines))
        let lower = out.lowercased()
        let hits = testCase.mustNotContain.filter { lower.contains($0) }
        check = hits.isEmpty ? "ok" : "PRÜFEN: „\(hits.joined(separator: "“, „"))“"
        if testCase.group == "grenze" {
            check = "PRÜFEN: Antwort statt Fehler (Eingabe \(testCase.text.count) Z., Antwort \(out.count) Z.)"
        }
        if showFull { fullOutputs.append("### \(testCase.group) · \(testCase.label)\n\n\(out)\n") }
    } catch let error as AppleIntelligenceError {
        result = "FEHLER .\(error)"
        rejected = error == .rejected ? "JA" : "nein"
        check = testCase.group == "grenze" && error == .textTooLong ? "ok (Fehler statt halbem Text)" : "FEHLER"
    } catch {
        result = "FEHLER \(type(of: error))"
        check = "FEHLER"
    }
    let seconds = Date().timeIntervalSince(start)
    var skipped = testCase.group == "bereinigung" && testCase.text.count < minChars ? " (App: < \(minChars) Z., übersprungen)" : ""
    if testCase.group == "grenze" { skipped += " (\(await tokens(testCase.instructions + testCase.text)))" }
    return "| \(testCase.group) | \(testCase.label)\(skipped) | \(String(format: "%.2f s", seconds)) | \(rejected) | \(check) | \(result) |"
}

print("Apple Intelligence — Messung \(ISO8601DateFormatter().string(from: Date()))")
print("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("Diktat-Mindestlänge laut Code: \(minChars) Zeichen\n")
print("| Gruppe | Fall | Zeit | abgelehnt | Prüfung | Ergebnis (gekürzt) |")
print("|---|---|---|---|---|---|")
for testCase in cases {
    print(await run(testCase, guardrails: .permissive))
}
// Gegenprobe: Dampf ablassen mit Apples Standard-Filter statt des Umformulier-Modus.
if cases.contains(where: { $0.group == "defuse" }) {
    print("\nGegenprobe Dampf ablassen mit Standard-Inhaltsfilter (nicht ausgeliefert):\n")
    print("| Gruppe | Fall | Zeit | abgelehnt | Prüfung | Ergebnis (gekürzt) |")
    print("|---|---|---|---|---|---|")
    for testCase in cases where testCase.group == "defuse" {
        print(await run(testCase, guardrails: .standard))
    }
}

if showFull {
    print("\n## Volle Antworten\n")
    fullOutputs.forEach { print($0) }
}
