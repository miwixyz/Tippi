import CoreGraphics
import Foundation

// Reine Entscheidungen der Autovervollständigung — ohne Fenster, ohne
// Bedienungshilfen, ohne Netz, damit jede Sicherheitsregel aus
// docs/SECURE-DESIGN-autocomplete.md als Unit-Test festgenagelt werden kann.
// Die Verdrahtung mit dem System steht in `AutocompleteController`.

// MARK: - Kontext vor dem Cursor

enum AutocompleteContext {
    /// Design §1/§3: höchstens 400 Zeichen (UTF-16-Einheiten) vor dem Cursor.
    static let maxUTF16 = 400
    /// Design §3: unter 3 Zeichen Kontext keine Anfrage.
    static let minCharacters = 3

    /// Text vor `cursorUTF16`, auf `limit` UTF-16-Einheiten gekürzt.
    ///
    /// Geschnitten wird nur an Zeichengrenzen (Graphem-Clustern): ein Emoji
    /// oder ein ZWJ-Familien-Emoji wird entweder ganz mitgenommen oder gar
    /// nicht — nie eine halbe Surrogat-Hälfte. Liegt der Cursor mitten in einem
    /// Zeichen, wird abgerundet. Ein Cursor hinter dem Textende wird geklemmt.
    static func beforeCursor(in text: String, cursorUTF16: Int, limit: Int = maxUTF16) -> String {
        guard cursorUTF16 > 0, limit > 0 else { return "" }
        let utf16 = text.utf16
        var end = utf16.index(utf16.startIndex, offsetBy: min(cursorUTF16, utf16.count))
        while end > text.startIndex, end.samePosition(in: text) == nil {
            end = utf16.index(before: end)
        }
        var start = utf16.index(end, offsetBy: -limit, limitedBy: text.startIndex) ?? text.startIndex
        while start < end, start.samePosition(in: text) == nil {
            start = utf16.index(after: start)
        }
        var result = String(text[start..<end])
        // Liest die App einen Bereich, der mitten in einem Zeichen beginnt,
        // steht vorne ein Ersatzzeichen — für das Modell nur Rauschen.
        while result.first == "\u{FFFD}" { result.removeFirst() }
        return result
    }

    /// Genug Kontext für eine Anfrage? (Design §3: mindestens 3 Zeichen.)
    static func isLongEnough(_ context: String) -> Bool {
        context.trimmingCharacters(in: .whitespacesAndNewlines).count >= minCharacters
    }

    /// Nur vorschlagen, wenn hinter dem Cursor nichts auf derselben Zeile steht.
    /// Mitten im Satz würde das Overlay den folgenden Text überdecken.
    static func cursorIsAtLineEnd(nextCharacter: Character?) -> Bool {
        guard let next = nextCharacter else { return true }
        return next.isWhitespace
    }
}

// MARK: - Ausschluss (Design §3 „Information disclosure — Passwortfelder")

enum AutocompleteExclusion {
    /// Design §3: nur Text-Rollen.
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    static let secureTextFieldRole = "AXSecureTextField"

    enum Reason: String, Equatable {
        case secureInput, secureField, unknownApp, tippiItself, excludedApp, notTextRole
    }

    /// `nil` = darf gelesen werden. Reihenfolge: die harten Passwort-Signale
    /// zuerst, damit sie nie von einer späteren Regel überdeckt werden.
    static func reason(
        bundleID: String?,
        role: String?,
        subrole: String?,
        secureInputActive: Bool,
        excludedBundleIDs: Set<String>,
        ownBundleID: String?
    ) -> Reason? {
        if secureInputActive { return .secureInput }
        if role == secureTextFieldRole || subrole == secureTextFieldRole { return .secureField }
        // Ohne Bundle-ID lässt sich die Ausschlussliste nicht prüfen → nicht lesen.
        guard let bundleID else { return .unknownApp }
        if let ownBundleID, bundleID == ownBundleID { return .tippiItself }
        if excludedBundleIDs.contains(bundleID) { return .excludedApp }
        guard let role, textRoles.contains(role) else { return .notTextRole }
        return nil
    }
}

// MARK: - Tastatur-Tap (Design §3 „Tastatur → Tippi")

enum AutocompleteKeyDecision {
    static let tabKeyCode: Int64 = 48
    static let escapeKeyCode: Int64 = 53

    /// Was als Modifier zählt. Feststelltaste zählt nicht — mit ihr ist ⇥ immer
    /// noch ein schlichtes ⇥.
    static let modifierMask: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
    ]

    /// Der einzige Fall, in dem der Tap eine Taste schluckt: ⇥ ohne Modifier,
    /// während ein Vorschlag sichtbar ist. Alles andere läuft unverändert durch —
    /// sonst wäre z. B. die Einrückung im Code-Editor kaputt (Design §5).
    static func shouldSwallow(keyCode: Int64, flags: CGEventFlags, suggestionVisible: Bool) -> Bool {
        suggestionVisible && keyCode == tabKeyCode && flags.isDisjoint(with: modifierMask)
    }

    /// Soll nach dieser Taste die Pause neu gemessen werden? Nicht bei Esc (der
    /// Nutzer will den Vorschlag weghaben) und nicht bei ⌘/⌃-Kurzbefehlen.
    static func restartsPause(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode != escapeKeyCode && flags.isDisjoint(with: [.maskCommand, .maskControl])
    }
}

// MARK: - Bereinigung der Modellantwort (Design §3 „Tampering der Ausgabe")

enum AutocompleteSanitizer {
    static let maxWords = 3
    static let maxCharacters = 40

    /// Bidi-Steuerzeichen: könnten den angezeigten Vorschlag optisch anders
    /// aussehen lassen, als er eingefügt wird. ZWJ bleibt — Emoji brauchen ihn.
    private static let bidiControls: Set<UInt32> = [
        0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    /// Macht aus der rohen Modellantwort den Text, der angezeigt und auf ⇥
    /// eingefügt wird — oder `nil`, wenn nichts Brauchbares übrig bleibt.
    ///
    /// Das Ergebnis beginnt mit einem Leerzeichen, wenn ein neues Wort anfängt,
    /// und ohne, wenn es das angefangene Wort vervollständigt („vermis" → „se").
    /// `isKnownWord` entscheidet den unklaren Fall „Buchstabe trifft Buchstabe";
    /// in der App ist das die Rechtschreibprüfung.
    static func clean(_ raw: String, context: String, isKnownWord: (String) -> Bool = { _ in false }) -> String? {
        // 1. Nur die erste nicht-leere Zeile — Mehrzeilen-Vorschläge gibt es nicht (§6).
        let firstLine = raw
            .components(separatedBy: .newlines)
            .map(stripControls)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let line = firstLine else { return nil }

        // 2. Wiederholung des Getippten entfernen.
        let modelHadLeadingSpace = line.first?.isWhitespace ?? false
        var body = String(line.drop { $0.isWhitespace })
        var completesWord = false
        if let overlap = overlapLength(context: context, suggestion: body) {
            body = String(body.dropFirst(overlap))
            completesWord = !(body.first?.isWhitespace ?? true)
            if body.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        }

        // 3. Anschluss an den Kontext.
        let joined = join(body, context: context, modelHadLeadingSpace: modelHadLeadingSpace,
                          completesWord: completesWord, isKnownWord: isKnownWord)

        // 4. Kürzen.
        return truncate(joined)
    }

    private static func stripControls(_ text: String) -> String {
        // Steuerzeichen (auch ⇥) werden zu Leerzeichen, damit keine Wörter
        // zusammenkleben; Bidi-Steuerzeichen verschwinden ersatzlos.
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !bidiControls.contains(scalar.value) {
            scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(scalars)
    }

    /// Kürzeste Überlappung, die als Wiederholung zählt. Bei einem einzelnen
    /// Zeichen wäre „I have a" + „apple" sonst „I have apple".
    static let minOverlap = 2

    /// Länge (in Zeichen) des längsten Endes von `context`, mit dem `suggestion`
    /// beginnt — nur ab einer Wortgrenze im Kontext, sonst hielte „Ich esse" +
    /// „sehr gut" das „se" für eine Wiederholung. Groß-/Kleinschreibung egal.
    /// Beispiel (gemessen 2026-09-25): „…dass ich" + „dass ich dich vermisse."
    static func overlapLength(context: String, suggestion: String) -> Int? {
        let ctx = Array(context)
        let sug = Array(suggestion)
        guard ctx.count >= minOverlap, sug.count >= minOverlap else { return nil }
        for length in stride(from: min(ctx.count, sug.count), through: minOverlap, by: -1) {
            let start = ctx.count - length
            let atWordBoundary = start == 0 || ctx[start - 1].isWhitespace
            guard atWordBoundary, !ctx[start].isWhitespace else { continue }
            let matches = (0..<length).allSatisfy { ctx[start + $0].lowercased() == sug[$0].lowercased() }
            if matches { return length }
        }
        return nil
    }

    private static func join(_ body: String, context: String, modelHadLeadingSpace: Bool,
                             completesWord: Bool, isKnownWord: (String) -> Bool) -> String {
        let trimmed = String(body.drop { $0.isWhitespace })
        guard let last = context.last, !last.isWhitespace else {
            return trimmed        // Kontext endet mit Leerzeichen/leer → kein zweites
        }
        if completesWord || "([{„«".contains(last) { return trimmed }
        guard let first = trimmed.first else { return trimmed }
        if body.first?.isWhitespace == true { return " " + trimmed }
        if first.isPunctuation && !"(„\"'«»".contains(first) { return trimmed }
        if first.isLetter, last.isLetter, !modelHadLeadingSpace {
            let lastWord = String(context.reversed().prefix { !$0.isWhitespace }.reversed())
            let firstWord = String(trimmed.prefix { !$0.isWhitespace && !$0.isPunctuation })
            if isKnownWord(lastWord + firstWord) { return trimmed }
        }
        return " " + trimmed
    }

    /// Höchstens `maxWords` Wörter, höchstens bis zum Satzende, höchstens
    /// `maxCharacters` Zeichen — gekürzt wird an Wortgrenzen. Passt schon das
    /// erste Wort nicht, lieber kein Vorschlag als ein halbes Wort.
    static func truncate(_ text: String) -> String? {
        let leadingSpace = text.first?.isWhitespace == true
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        for word in words.prefix(maxWords) {
            kept.append(word)
            if let end = word.last, ".!?…".contains(end) { break }
        }
        while !kept.isEmpty {
            let candidate = (leadingSpace ? " " : "") + kept.joined(separator: " ")
            if candidate.count <= maxCharacters { return candidate }
            kept.removeLast()
        }
        return nil
    }
}

// MARK: - Anfrage an das lokale Modell (Design §3 „Tippi → Modellserver")

enum AutocompleteRequest {
    /// Design §3: Zeitlimit 1,5 s.
    static let timeout: TimeInterval = 1.5
    /// Gemessen 2026-09-25 (Gemma 4 E2B): ~20 Token, temperature 0.2, 6/6 Vorschläge.
    static let maxTokens = 20
    static let temperature = 0.2
    /// Nur nicht-privilegierte Ports (Bereichsprüfung, Design §3).
    static let allowedPorts = 1024...65_535

    static let systemPrompt = """
        Setze den Text des Nutzers fort, in seiner Sprache. Gib NUR die Fortsetzung aus: \
        1 bis 3 Wörter, höchstens bis zum Satzende. Wiederhole den Anfang nicht. \
        Endet der Text mitten in einem Wort, beginne mit dem Rest dieses Wortes.
        """

    /// Fest `http://127.0.0.1:<port>` — nie ein Hostname, der anders aufgelöst
    /// werden könnte, nie ein Cloud-Anbieter.
    static func loopbackURL(port: Int) -> URL? {
        guard allowedPorts.contains(port) else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http", url.host == "127.0.0.1",
              let port = url.port, allowedPorts.contains(port) else { return false }
        return url.user == nil && url.password == nil
    }

    struct ChatTemplateKwargs: Encodable { let enable_thinking: Bool }
    struct Message: Encodable { let role: String; let content: String }
    struct Body: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let max_tokens: Int
        let temperature: Double
        /// Ohne `enable_thinking: false` kam in 3 von 4 Messungen „Thinking
        /// Process…" statt eines Vorschlags (2026-09-25).
        let chat_template_kwargs: ChatTemplateKwargs
    }

    /// Die fertige Anfrage — oder `nil`, wenn `server` kein Loopback ist.
    static func make(server: URL, model: String, context: String) -> URLRequest? {
        guard isLoopback(server) else { return nil }
        let body = Body(
            model: model,
            messages: [Message(role: "system", content: systemPrompt),
                       Message(role: "user", content: context)],
            stream: false,
            max_tokens: maxTokens,
            temperature: temperature,
            chat_template_kwargs: ChatTemplateKwargs(enable_thinking: false)
        )
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        var request = URLRequest(url: server.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    /// `content` der ersten Antwort. `reasoning` wird bewusst nie gelesen —
    /// das ist das Selbstgespräch eines Thinking-Modells, kein Vorschlag.
    static func content(from data: Data) -> String? {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            let choices: [Choice]
        }
        return (try? JSONDecoder().decode(Response.self, from: data))?.choices.first?.message.content
    }
}

// MARK: - Platzierung

enum AutocompleteGeometry {
    /// Design §7: Wo Apps falsche Cursor-Bounds melden (Electron), lieber kein
    /// Vorschlag als ein falsch platzierter. Verworfen werden Rechtecke ohne
    /// Höhe, absurd große, der typische Nullpunkt-Müll und alles außerhalb
    /// der Bildschirme.
    static func isPlausibleCaret(_ rect: CGRect, screens: [CGRect]) -> Bool {
        guard rect.height >= 6, rect.height <= 200, rect.width >= 0, rect.width <= 400 else { return false }
        guard rect.origin != .zero else { return false }
        let probe = CGPoint(x: rect.midX, y: rect.midY)
        return screens.contains { $0.contains(probe) }
    }

    /// Schriftgröße passend zur Zeilenhöhe des Feldes, im Rahmen des Lesbaren.
    static func fontSize(forCaretHeight height: CGFloat) -> CGFloat {
        min(max(height * 0.8, 11), 28)
    }
}
