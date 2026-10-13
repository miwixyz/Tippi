import Foundation
import os

private let healingLog = Logger(subsystem: "com.tippi.app", category: "autocomplete")

// MARK: - Wortheilung: Vorschläge mitten im Wort

/// Vervollständigt ein angefangenes Wort („…dazu zw" → „ingen, viel zu raten.").
///
/// **Warum (gemessen 2026-10-13, 80 Schnitte in echten deutschen Texten,
/// Gemma 4 E2B):** Mit der Chat-Anfrage traf Tippi mitten im Wort **0 von 40**
/// — das Modell überging das angefangene Wort („ku" → „können", „lauf" → „dann
/// kann das auch sein"). Gab man ihm den Satz als Beginn seiner Antwort vor,
/// setzte es zwar fort, aber an einer Wortstück-Grenze, die es nie gelernt hat
/// („zw" → „zwirren"). Die Wortheilung traf **20 von 40**, Median 0,55 s.
///
/// **Wie:** Das Modell bekommt den Satz bis *vor* das angefangene Wort als Beginn
/// seiner Antwort. Beim nächsten Wortstück sind über `logit_bias` nur Stücke
/// erlaubt, die mit dem Getippten beginnen (oder selbst ein Anfang davon sind —
/// dann folgt ein weiterer Schritt). Ist der Wortanfang verbraucht, schreibt das
/// Modell frei weiter.
///
/// **mlx-lm-Fehler (0.31.3 und 0.32.0, gemessen 2026-10-13):** Ist eine Anfrage
/// genau die vorige Anfrage plus das dabei erzeugte Wortstück, stirbt der
/// Rechen-Thread des Servers (`insert_segments`: IndexError bzw. „empty
/// prompt") und **jede weitere Anfrage hängt** — auch Diktat und Umschreiben.
/// Deshalb erzeugt jeder Schritt `stepTokens` = 2 Stücke, von denen nur das
/// erste zählt: Der Zwischenspeicher hält dann vorige Anfrage + zwei Stücke, und
/// die nächste Anfrage ist ein echter Anfang davon. 133 Anfragen ohne Fehler;
/// ohne diesen Kniff hing der Server beim ersten Fall. Den Zwischenspeicher
/// abzuschalten hätte jedes Umschreiben/Diktat um ~0,2 s verlangsamt.
///
/// Nur für Modelle mit bekannter Gesprächsvorlage (`supports`). Alle anderen
/// Fälle laufen wie bisher über die Chat-Anfrage.
enum AutocompleteWordHealing {
    /// Kurz gehalten: Steht vor dem Satz kein Text, schreibt das Modell sonst
    /// Teile der Anweisung ab („zwingen, in seiner Sprache und seinem Stil zu").
    /// Gemessen 2026-10-13 an 40 Satzanfängen: lange Anweisung 14 Treffer, diese
    /// 20; an den 80 Fällen mit Text davor 22 statt 20 von 40.
    static let systemPrompt = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."

    /// Wörter der Anweisung (ab 4 Buchstaben) plus „acht" für die „8".
    static let instructionWords: Set<String> = Set(
        systemPrompt.split { !$0.isLetter }.filter { $0.count >= 4 }.map { $0.lowercased() }
    ).union(["acht"])

    /// Taucht in der Fortsetzung ein Wort der Anweisung auf, bleibt nur der Rest
    /// des angefangenen Wortes. Gemessen 2026-10-13: 2 von 40 Satzanfängen
    /// enthielten Anweisungstext („…die Fortsetzung höchstens acht Wörter zu
    /// geben."), mit diesem Filter 0, bei unveränderten 20 Treffern.
    static func withoutInstructionEcho(_ suggestion: String) -> String {
        let wordEnd = suggestion.firstIndex { $0.isWhitespace || ",.;:!?".contains($0) } ?? suggestion.endIndex
        let rest = suggestion[wordEnd...]
        let echoes = rest.split { !$0.isLetter }.contains { instructionWords.contains($0.lowercased()) }
        return echoes ? String(suggestion[..<wordEnd]) : suggestion
    }
    /// Höchstens so viele Wortstücke, bis der getippte Anfang verbraucht ist.
    static let maxSteps = 4
    /// Siehe mlx-lm-Fehler oben: nie 1.
    static let stepTokens = 2
    static let continuationTokens = 20
    /// Zuschlag für erlaubte Stücke — groß genug, dass nur sie in Frage kommen.
    static let allowedBias = 100.0

    /// Gemma 4 — die einzige Vorlage, die hier nachgebaut ist (`promptHead`).
    static func supports(model: String) -> Bool {
        model.lowercased().contains("gemma-4")
    }

    struct Split: Equatable {
        /// Text vor dem aktuellen Satz (geht als Nutzertext ans Modell).
        let before: String
        /// Satzanfang bis vor das angefangene Wort (Beginn der Modellantwort).
        let base: String
        /// Das angefangene Wort.
        let started: String
    }

    /// `nil`, wenn `line` nicht mitten in einem Wort endet.
    static func split(_ line: String) -> Split? {
        let isWordChar: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let last = line.last, isWordChar(last) else { return nil }
        let started = String(line.reversed().prefix(while: isWordChar).reversed())
        return sentenceSplit(head: Array(line.dropLast(started.count)), started: started)
    }

    /// Am Wortanfang (Zeile endet mit Leerzeichen): derselbe Satz-als-Antwortbeginn,
    /// nur ohne Beschränkung der Wortstücke. Gemessen 2026-10-13 an 40 Stellen: die
    /// Chat-Anfrage traf 2, und 15 Antworten wiederholten den Satzanfang (vom
    /// Wiederholungsfilter verworfen → kein Vorschlag); so 4 Treffer. Mit `startsNewWord`
    /// bleiben trotzdem 15 von 40 ohne Vorschlag (Leerzeichen behalten: 1 Treffer; erstes
    /// Stück auf „Leerzeichen + Buchstabe“ beschränken: 4 Treffer, 8 leer, aber 0,66 s und
    /// 136 000 Bias-Einträge je Anfrage — verworfen).
    static func splitAtWordStart(_ line: String) -> Split? {
        guard line.last == " " else { return nil }
        return sentenceSplit(head: Array(line), started: "")
    }

    private static func sentenceSplit(head: [Character], started: String) -> Split {
        // Satzgrenze: Zeilenumbruch oder .!?: gefolgt von Leerraum.
        var cut = 0
        for index in stride(from: head.count - 1, through: 0, by: -1) {
            if head[index].isNewline { cut = index + 1; break }
            if ".!?:".contains(head[index]), index + 1 < head.count, head[index + 1].isWhitespace {
                cut = index + 1
                break
            }
        }
        var baseStart = cut
        while baseStart < head.count, head[baseStart].isWhitespace { baseStart += 1 }
        return Split(before: String(head[..<baseStart]), base: String(head[baseStart...]), started: started)
    }

    /// Der getippte Wortanfang, wie das Modell ihn als Wortstücke sieht: mit
    /// Leerzeichen davor, wenn im Satz schon etwas steht.
    static func openPrefix(_ split: Split) -> String {
        guard !split.started.isEmpty else { return "" }
        return (split.base.isEmpty ? "" : " ") + split.started
    }

    /// Gemma-4-Vorlage bis zum Beginn der Modellantwort, plus der Satzanfang.
    static func prompt(system: String, split: Split) -> String {
        let user = neutralized(split.before).trimmingCharacters(in: .whitespacesAndNewlines)
        var base = neutralized(split.base)
        while base.last == " " { base.removeLast() }
        return "<|turn>system\n\(neutralized(system))<turn|>\n<|turn>user\n\(user.isEmpty ? "(Textanfang)" : user)<turn|>\n<|turn>model\n" + base
    }

    /// Gemmas Sonderzeichen ohne senkrechten Strich (Rafter-Review 2026-10-13).
    static let plainSpecialTokens = ["bos", "eos", "pad", "unk", "mask"]

    /// Getippter Text darf keine Steuermarken der Vorlage bilden („<|turn>",
    /// „<eos>") — sonst liest der Tokenizer sie als echte Sonderzeichen.
    static func neutralized(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<|", with: "<").replacingOccurrences(of: "|>", with: ">")
        for name in plainSpecialTokens {
            result = result.replacingOccurrences(of: "<\(name)>", with: "‹\(name)›", options: .caseInsensitive)
        }
        return result
    }

    enum Step: Equatable {
        /// Wortanfang verbraucht; `tail` ist der Rest des Wortes aus diesem Stück.
        case finished(tail: String)
        /// Stück war ein Teil des Anfangs; `rest` ist noch offen.
        case partial(rest: String)
        /// Stück passt nicht (darf bei korrektem `logit_bias` nicht vorkommen).
        case mismatch
    }

    static func step(rest: String, piece: String) -> Step {
        if piece.hasPrefix(rest) { return .finished(tail: String(piece.dropFirst(rest.count))) }
        if !piece.isEmpty, rest.hasPrefix(piece) { return .partial(rest: String(rest.dropFirst(piece.count))) }
        return .mismatch
    }

    /// Am Wortanfang (der Nutzer hat schon ein Leerzeichen getippt) zählt nur eine
    /// Fortsetzung, die mit einem neuen Wort beginnt. Gemessen 2026-10-13 in
    /// TextEdit: Der Satzanfang endet für das Modell ohne das Leerzeichen, es setzte
    /// sonst das letzte Wort fort („Mac " → „hen") oder hängte Satzzeichen an
    /// („laufen " → „.").
    static func startsNewWord(_ continuation: String) -> Bool {
        guard let first = continuation.first, first.isWhitespace else { return false }
        return continuation.dropFirst().first.map { $0.isLetter || $0.isNumber || "„\"'(".contains($0) } ?? false
    }

    /// Darf `piece` als nächstes Stück kommen, solange `rest` offen ist?
    static func isAllowed(_ piece: String, rest: String) -> Bool {
        !piece.isEmpty && (piece.hasPrefix(rest) || (piece.count >= 2 && rest.hasPrefix(piece)))
    }

    /// Fortsetzung nach dem Wortanfang: nur die erste Zeile, ohne Vorlagen-Ende.
    ///
    /// `cutAtLength`: Die Antwort endete an der Längengrenze (`finish_reason`
    /// „length"). Dann fällt das letzte Wort weg — es ist meist abgeschnitten, und
    /// vor allem: Übernähme man die **ganze** Antwort, wäre die nächste Anfrage
    /// genau „vorige Anfrage + Antwort" — der mlx-lm-Fall, der den Server aufhängt
    /// (gemessen 2026-10-13: „…bringe" + „ meine Sachen" → Server hängt). Endet
    /// die Antwort von selbst, liegt das Ende-Zeichen im Zwischenspeicher, und die
    /// nächste Anfrage ist ein echter Anfang davon (gemessen: kein Hänger).
    static func continuation(_ raw: String, cutAtLength: Bool = false) -> String {
        let text = raw.components(separatedBy: "<turn|>").first ?? raw
        let line = text.components(separatedBy: .newlines).first ?? text
        guard cutAtLength else { return line }
        guard let lastSpace = line.lastIndex(where: \.isWhitespace) else { return "" }
        return String(line[..<lastSpace])
    }
}

// MARK: - Ablauf gegen den lokalen Server

/// Eine Wortheilung: bis zu `maxSteps` beschränkte Schritte, dann die freie
/// Fortsetzung. `fetch` ist der Netzweg des Controllers (eigene Sitzung, kein
/// Proxy, keine Weiterleitung).
@MainActor
struct AutocompleteHealingRun {
    let server: URL
    let model: String
    let fetch: (URLRequest) async -> Data?

    /// Rest des Wortes + Fortsetzung, roh (führendes Leerzeichen = das getippte
    /// Wort war schon fertig) — oder `nil`.
    func suggestion(_ split: AutocompleteWordHealing.Split, vocabulary: AutocompleteVocabulary,
                    glossary: [String]) async -> String? {
        typealias Healing = AutocompleteWordHealing
        let system = AutocompleteRequest.systemPrompt(glossary: glossary, base: Healing.systemPrompt)
        var prompt = Healing.prompt(system: system, split: split)
        var rest = Healing.openPrefix(split)
        // Am Wortanfang gibt es nichts zu heilen — gleich frei weiterschreiben.
        var tail: String? = rest.isEmpty ? "" : nil
        // Messpunkt (2026-10-13, erster Lauf 1,4–1,5 s statt 0,55 s gemessen):
        // Schritte, Suchzeit, Gesamtzeit — nie Text.
        let started = Date()
        var steps = 0
        var lookupSeconds: TimeInterval = 0
        defer {
            healingLog.notice("heal steps=\(steps, privacy: .public) lookupMs=\(Int(lookupSeconds * 1000), privacy: .public) totalMs=\(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) found=\(tail != nil, privacy: .public)")
        }
        while tail == nil, steps < Healing.maxSteps {
            steps += 1
            let lookupStart = Date()
            let allowed = vocabulary.allowedIDs(rest: rest)
            lookupSeconds += Date().timeIntervalSince(lookupStart)
            guard !allowed.isEmpty, !Task.isCancelled,
                  let request = AutocompleteRequest.makeCompletion(
                      server: server, model: model, prompt: prompt,
                      maxTokens: Healing.stepTokens, allowedTokenIDs: allowed),
                  let data = await fetch(request),
                  let id = AutocompleteRequest.completion(from: data)?.firstTokenID,
                  let piece = vocabulary.piece(id) else { return nil }
            prompt += Healing.neutralized(piece)
            switch Healing.step(rest: rest, piece: piece) {
            case .finished(let wordTail): tail = wordTail
            case .partial(let open): rest = open
            case .mismatch: return nil
            }
        }
        guard let tail, !Task.isCancelled,
              let request = AutocompleteRequest.makeCompletion(
                  server: server, model: model, prompt: prompt, maxTokens: Healing.continuationTokens),
              let data = await fetch(request),
              let answer = AutocompleteRequest.completion(from: data) else { return nil }
        let more = Healing.continuation(answer.text, cutAtLength: answer.finishReason == "length")
        if split.started.isEmpty, !Healing.startsNewWord(more) { return nil }
        return Healing.withoutInstructionEcho(tail + more)
    }
}

// MARK: - Wortstücke je Modell, einmal im Hintergrund geladen

@MainActor
final class AutocompleteVocabularyCache {
    /// `value == nil`: Laden gescheitert — dann bleibt es beim bisherigen Weg.
    private var loaded: (model: String, value: AutocompleteVocabulary?)?
    private var loading: String?

    /// Die Wortstücke für `model` — oder `nil`, solange sie laden oder nicht
    /// ladbar sind. Gemessen 2026-10-13: 262.144 Stücke in ~1,1 s.
    func vocabulary(for model: String) -> AutocompleteVocabulary? {
        guard AutocompleteWordHealing.supports(model: model) else { return nil }
        if let loaded, loaded.model == model { return loaded.value }
        guard loading != model else { return nil }
        loading = model
        Task.detached(priority: .utility) { [weak self] in
            let started = Date()
            let vocabulary = AutocompleteVocabulary.load(model: model)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            await MainActor.run {
                guard let self else { return }
                self.loading = nil
                self.loaded = (model, vocabulary)
                healingLog.notice("vocabulary \(vocabulary == nil ? "unavailable" : "loaded", privacy: .public) pieces=\(vocabulary?.pieces.count ?? 0, privacy: .public) ms=\(ms, privacy: .public)")
            }
        }
        return nil
    }
}

// MARK: - Rohtext-Anfrage an `/v1/completions`

extension AutocompleteRequest {
    struct CompletionBody: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let max_tokens: Int
        let temperature: Double
        /// Wortstück-Nummer (als Text, so verlangt es das JSON) → Zuschlag.
        let logit_bias: [String: Double]?
        /// Nur damit die Nummer des ersten erzeugten Wortstücks zurückkommt.
        let logprobs: Bool?
    }

    struct CompletionLogProbs: Decodable {
        struct Entry: Decodable { let id: Int }
        let content: [Entry]?
    }

    /// Anfrage mit fertigem Prompt — oder `nil`, wenn `server` kein Loopback
    /// ist (dieselbe Regel wie bei `make`).
    static func makeCompletion(server: URL, model: String, prompt: String, maxTokens: Int,
                               allowedTokenIDs: [Int]? = nil) -> URLRequest? {
        guard isLoopback(server) else { return nil }
        let bias = allowedTokenIDs.map { ids in
            Dictionary(uniqueKeysWithValues: ids.map { (String($0), AutocompleteWordHealing.allowedBias) })
        }
        let body = CompletionBody(model: model, prompt: prompt, stream: false, max_tokens: maxTokens,
                                  temperature: 0, logit_bias: bias, logprobs: bias == nil ? nil : true)
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        var request = URLRequest(url: server.appendingPathComponent("v1/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    /// Text und Nummer des ersten Wortstücks einer `/v1/completions`-Antwort.
    static func completion(from data: Data) -> (text: String, firstTokenID: Int?, finishReason: String?)? {
        struct Response: Decodable {
            struct Choice: Decodable {
                let text: String?
                let logprobs: CompletionLogProbs?
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let choice = (try? JSONDecoder().decode(Response.self, from: data))?.choices.first else { return nil }
        return (choice.text ?? "", choice.logprobs?.content?.first?.id, choice.finish_reason)
    }
}

// MARK: - Wortstücke des Modells

/// Die Wortstücke des lokalen Modells, gelesen aus dessen `tokenizer.json` im
/// Hugging-Face-Zwischenspeicher — dieselbe Datei, die `mlx_lm.server` lädt.
/// Nur lesen, nichts wird geschrieben oder gesendet.
final class AutocompleteVocabulary: @unchecked Sendable {
    /// Index = Nummer des Stücks; "" für Sonder- und Byte-Stücke.
    let pieces: [String]
    /// Alle Stücke als NFC-Bytes, sortiert — Stücke mit gleichem Anfang liegen
    /// am Stück. Gemessen 2026-10-13: Die Komplettsuche über 262.144 Stücke kostete
    /// 58 ms je Schritt, auf dem Hauptthread neben dem Tastatur-Abfang.
    private let sorted: [(bytes: [UInt8], id: Int)]
    /// NFC-Stück → Nummer, für die kürzeren Stücke, die selbst ein Anfang sind.
    private let byPiece: [String: Int]

    init(pieces: [String]) {
        self.pieces = pieces
        var sorted: [(bytes: [UInt8], id: Int)] = []
        var byPiece: [String: Int] = [:]
        for (id, piece) in pieces.enumerated() where !piece.isEmpty {
            let normalized = piece.precomposedStringWithCanonicalMapping
            sorted.append((Array(normalized.utf8), id))
            if byPiece[normalized] == nil { byPiece[normalized] = id }
        }
        sorted.sort { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        self.sorted = sorted
        self.byPiece = byPiece
    }

    /// Schutz gegen eine fremde oder kaputte Datei.
    static let maxFileBytes = 100_000_000

    func piece(_ id: Int) -> String? {
        pieces.indices.contains(id) ? pieces[id] : nil
    }

    /// Dieselbe Menge wie `pieces.filter { AutocompleteWordHealing.isAllowed($0, rest:) }`,
    /// nur über den sortierten Index: Stücke, die mit `rest` beginnen, plus
    /// Stücke ab 2 Zeichen, die selbst ein Anfang von `rest` sind.
    func allowedIDs(rest: String) -> [Int] {
        let normalized = rest.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else { return [] }
        let key = Array(normalized.utf8)
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].bytes.lexicographicallyPrecedes(key) { low = mid + 1 } else { high = mid }
        }
        var ids: [Int] = []
        while low < sorted.count, sorted[low].bytes.starts(with: key) {
            ids.append(sorted[low].id)
            low += 1
        }
        var prefix = ""
        for character in normalized.dropLast() {
            prefix.append(character)
            if prefix.count >= 2, let id = byPiece[prefix] { ids.append(id) }
        }
        return ids.sorted()
    }

    /// Wo `huggingface_hub` Modelle ablegt.
    static var hubDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if let cache = env["HF_HUB_CACHE"], !cache.isEmpty { return URL(fileURLWithPath: cache) }
        if let home = env["HF_HOME"], !home.isEmpty { return URL(fileURLWithPath: home).appendingPathComponent("hub") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub")
    }

    /// Ordnername im Zwischenspeicher — oder `nil` für eine Kennung, die kein
    /// `organisation/name` ist (kein Pfad außerhalb des Zwischenspeichers).
    static func cacheFolder(for model: String) -> String? {
        let parts = model.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && part.unicodeScalars.allSatisfy(allowed.contains)
        }) else { return nil }
        return "models--\(parts[0])--\(parts[1])"
    }

    static func load(model: String, hub: URL = hubDirectory) -> AutocompleteVocabulary? {
        guard let folder = cacheFolder(for: model) else { return nil }
        let snapshots = hub.appendingPathComponent(folder).appendingPathComponent("snapshots")
        let candidates = (try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? []
        for snapshot in candidates {
            let file = snapshot.appendingPathComponent("tokenizer.json")
            guard let size = (try? FileManager.default.attributesOfItem(atPath: file.resolvingSymlinksInPath().path))?[.size] as? Int,
                  size <= maxFileBytes,
                  let data = try? Data(contentsOf: file) else { continue }
            if let vocabulary = parse(data) { return vocabulary }
        }
        return nil
    }

    /// `model.vocab` einer BPE-`tokenizer.json`: Stück → Nummer. „▁" steht für
    /// ein Leerzeichen; Byte-Stücke (`<0x41>`) und Sonderzeichen bleiben leer.
    static func parse(_ data: Data) -> AutocompleteVocabulary? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              let vocab = model["vocab"] as? [String: Int],
              let maxID = vocab.values.max(), maxID >= 0, maxID < 2_000_000 else { return nil }
        let special = Set(((json["added_tokens"] as? [[String: Any]]) ?? []).compactMap { $0["content"] as? String })
        var pieces = [String](repeating: "", count: maxID + 1)
        for (piece, id) in vocab where id >= 0 && !special.contains(piece) && !isByteFallback(piece) {
            pieces[id] = piece.replacingOccurrences(of: "\u{2581}", with: " ")
        }
        return AutocompleteVocabulary(pieces: pieces)
    }

    private static func isByteFallback(_ piece: String) -> Bool {
        piece.count == 6 && piece.hasPrefix("<0x") && piece.hasSuffix(">")
    }
}
