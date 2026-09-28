import AppKit
import CoreGraphics
import Foundation
import NaturalLanguage

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
    /// Bearbeitbarer Web-Inhalt (Mail-Textkörper, gemessen 2026-09-25) — nur
    /// erlaubt, wenn er bearbeitbar ist; eine gelesene Webseite nie.
    static let webAreaRole = "AXWebArea"

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
        ownBundleID: String?,
        isEditable: Bool
    ) -> Reason? {
        if secureInputActive { return .secureInput }
        if role == secureTextFieldRole || subrole == secureTextFieldRole { return .secureField }
        // Ohne Bundle-ID lässt sich die Ausschlussliste nicht prüfen → nicht lesen.
        guard let bundleID else { return .unknownApp }
        if let ownBundleID, bundleID == ownBundleID { return .tippiItself }
        if excludedBundleIDs.contains(bundleID) { return .excludedApp }
        guard let role, textRoles.contains(role) || (role == webAreaRole && isEditable) else { return .notTextRole }
        return nil
    }
}

// MARK: - Übernahme-Tasten (frei belegbar)

/// Was eine Übernahme-Taste tut.
enum AutocompleteAcceptAction: Equatable {
    /// Nur das nächste Wort — der Rest bleibt stehen.
    case nextWord
    /// Den ganzen sichtbaren Rest auf einmal.
    case wholeSuggestion
}

/// Welche Tasten als Übernahme-Taste taugen (Design §3 „Tastatur → Tippi").
///
/// Der Tap schluckt die Taste, solange ein Vorschlag sichtbar ist — und der ist
/// nach jeder Tipppause sichtbar. Eine Taste, die beim Schreiben ein Zeichen
/// erzeugt, wäre dann ständig weg. Deshalb:
/// - ⇥, →, ↓ und F-Tasten mit jeder Sondertaste oder ohne;
/// - die Taste über ⇥ nur ganz ohne Sondertaste;
/// - jede andere Taste nur mit ⌘ oder ⌃ — solche Kombinationen tippen keinen
///   Text. ⇧ oder ⌥ allein erzeugen Zeichen (⇧A = „A", ⌥L = „@" auf deutscher
///   Tastatur) und reichen dort nicht;
/// - Esc nie — Esc verwirft den Vorschlag;
/// - nie ein Kürzel, das schon etwas anderes tut: ⌃Space/⌃⌥Space (Eingabequelle)
///   und Tippis eigene globale Hotkeys (`reserved`, kommt aus den Einstellungen).
/// Gleiche Taste für beide Aktionen wird nicht abgelehnt, sondern getauscht
/// (`AutocompleteKeyBindings.assigning`).
enum AutocompleteKeyRules {
    static let escapeKeyCode: UInt16 = 53
    static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,   // F1–F12
        105, 107, 113, 106, 64, 79, 80,                          // F13–F19
    ]
    /// Tippen keinen Text — mit jedem Modifier erlaubt: ⇥, →, ↓, F-Tasten.
    static let nonTextKeyCodes: Set<UInt16> = functionKeyCodes.union([48, 124, 125])
    /// Die Taste über ⇥. macOS meldet sie je nach Tastatur als 50 (ANSI „`")
    /// oder 10 (ISO, deutsch „^"). Erzeugt ein Zeichen — ohne Modifier trotzdem
    /// erlaubt, weil sie beim Schreiben von Fließtext kaum vorkommt. Auf ISO-
    /// Tastaturen ist 50 vermutlich „<" neben ⇧ und damit mit erlaubt —
    /// Restrisiko, siehe docs/SECURE-DESIGN-autocomplete.md §7.
    static let aboveTabKeyCodes: Set<UInt16> = [50, 10]
    /// Tasten, die macOS selbst immer mit dem Fn-Flag meldet (Pfeile, F-Tasten,
    /// Pos1/Ende/Bild/Entf). Bei ihnen ist Fn kein Modifier.
    static let fnFlagKeyCodes: Set<UInt16> = functionKeyCodes.union([123, 124, 125, 126, 115, 116, 117, 119, 121])
    /// macOS-Kürzel zum Wechseln der Eingabequelle (vorherige / nächste).
    static let systemReserved: [KeyCombo] = [
        KeyCombo(keyCode: 49, modifiers: [.control]),
        KeyCombo(keyCode: 49, modifiers: [.control, .option]),
    ]

    enum Problem: Equatable {
        /// Esc verwirft den Vorschlag.
        case escape
        /// Die Taste erzeugt beim Schreiben ein Zeichen (oder wird dafür gebraucht).
        case typesText
        /// Schon ein Kürzel von macOS oder ein eigener Tippi-Hotkey.
        case alreadyShortcut
    }

    /// `nil` = erlaubt. `reserved` = Tippis eigene globale Hotkeys.
    static func problem(_ combo: KeyCombo, reserved: [KeyCombo] = []) -> Problem? {
        if combo.keyCode == escapeKeyCode { return .escape }
        if systemReserved.contains(combo) || reserved.contains(combo) { return .alreadyShortcut }
        if nonTextKeyCodes.contains(combo.keyCode) { return nil }
        let mods = combo.modifiers
        if mods.contains(.command) || mods.contains(.control) { return nil }
        if mods.isEmpty && aboveTabKeyCodes.contains(combo.keyCode) { return nil }
        return .typesText
    }
}

/// Die zwei Übernahme-Tasten. Ab Werk ⇥ (ein Wort) und ⇧⇥ (alles) — ⇥ verhält
/// sich damit genau wie vor der freien Belegung.
struct AutocompleteKeyBindings: Equatable {
    var nextWord: KeyCombo
    var wholeSuggestion: KeyCombo

    static let defaultNextWord = KeyCombo(keyCode: UInt16(AutocompleteKeyDecision.tabKeyCode), modifiers: [])
    static let defaultWholeSuggestion = KeyCombo(keyCode: UInt16(AutocompleteKeyDecision.tabKeyCode), modifiers: [.shift])
    static let `default` = AutocompleteKeyBindings(nextWord: defaultNextWord, wholeSuggestion: defaultWholeSuggestion)

    func combo(for action: AutocompleteAcceptAction) -> KeyCombo {
        action == .nextWord ? nextWord : wholeSuggestion
    }

    /// Legt `combo` auf `action`. Hat die andere Aktion diese Taste schon,
    /// bekommt sie die bisherige Taste von `action` — getauscht statt
    /// abgelehnt, sonst ließen sich die zwei Tasten nie gegeneinander tauschen.
    /// `swapped` = die andere Aktion hat sich mitgeändert (Hinweis zeigen).
    func assigning(_ combo: KeyCombo, to action: AutocompleteAcceptAction)
        -> (bindings: AutocompleteKeyBindings, swapped: Bool) {
        var result = self
        let previous = self.combo(for: action)
        let other = action == .nextWord ? wholeSuggestion : nextWord
        let swapped = other == combo && previous != combo
        switch action {
        case .nextWord:
            result.nextWord = combo
            if swapped { result.wholeSuggestion = previous }
        case .wholeSuggestion:
            result.wholeSuggestion = combo
            if swapped { result.nextWord = previous }
        }
        return (result, swapped)
    }

    /// Ein immer gültiges Paar aus gespeicherten Werten: Fehlendes oder
    /// Unerlaubtes fällt auf den Standard zurück, eine Doppelbelegung ebenso.
    /// Die Einstellungen lassen nichts anderes zu — das hier schützt vor einer
    /// von Hand bearbeiteten Plist: Der Tap darf nie z. B. „a" schlucken.
    static func sanitized(nextWord: KeyCombo?, wholeSuggestion: KeyCombo?) -> AutocompleteKeyBindings {
        func valid(_ combo: KeyCombo?) -> KeyCombo? {
            // Neu aufgebaut: Decodable übernimmt `modifiersRaw` ungefiltert, der
            // Initializer lässt nur ⌘⌃⌥⇧ stehen (Feststell-/Fn-Bits aus einer
            // bearbeiteten Plist ergäben sonst eine Taste, die nie greift).
            combo.map { KeyCombo(keyCode: $0.keyCode, modifiers: $0.modifiers) }
                .flatMap { AutocompleteKeyRules.problem($0) == nil ? $0 : nil }
        }
        let next = valid(nextWord) ?? defaultNextWord
        var whole = valid(wholeSuggestion) ?? defaultWholeSuggestion
        if whole == next {
            whole = next == defaultWholeSuggestion ? defaultNextWord : defaultWholeSuggestion
        }
        return AutocompleteKeyBindings(nextWord: next, wholeSuggestion: whole)
    }
}

// MARK: - Tastatur-Tap (Design §3 „Tastatur → Tippi")

enum AutocompleteKeyDecision {
    static let tabKeyCode: Int64 = 48
    static let escapeKeyCode: Int64 = 53

    /// Die vier Modifier, die `KeyCombo` kennt. Feststelltaste, Fn und
    /// Ziffernblock-Flag gehören nicht dazu — mit Feststelltaste ist ⇥ immer
    /// noch ein schlichtes ⇥.
    static func modifiers(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    /// Genau diese Taste mit genau diesen Modifiern — ⇧⌘⇥ ist nicht ⇧⇥.
    /// Fn zählt wie bisher als Modifier (fn-⇥ ist kein ⇥), außer bei Tasten,
    /// die macOS immer mit Fn meldet (Pfeile, F-Tasten).
    static func matches(_ combo: KeyCombo, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == Int64(combo.keyCode) else { return false }
        if flags.contains(.maskSecondaryFn), !AutocompleteKeyRules.fnFlagKeyCodes.contains(combo.keyCode) {
            return false
        }
        return modifiers(from: flags) == combo.modifiers
    }

    /// Der einzige Fall, in dem der Tap eine Taste schluckt: eine der zwei
    /// Übernahme-Tasten, während ein Vorschlag sichtbar ist. Alles andere läuft
    /// unverändert durch — sonst wäre z. B. die Einrückung im Code-Editor
    /// kaputt (Design §5).
    static func action(keyCode: Int64, flags: CGEventFlags, suggestionVisible: Bool,
                       bindings: AutocompleteKeyBindings) -> AutocompleteAcceptAction? {
        guard suggestionVisible else { return nil }
        if matches(bindings.nextWord, keyCode: keyCode, flags: flags) { return .nextWord }
        if matches(bindings.wholeSuggestion, keyCode: keyCode, flags: flags) { return .wholeSuggestion }
        return nil
    }

    static func shouldSwallow(keyCode: Int64, flags: CGEventFlags, suggestionVisible: Bool,
                              bindings: AutocompleteKeyBindings = .default) -> Bool {
        action(keyCode: keyCode, flags: flags, suggestionVisible: suggestionVisible, bindings: bindings) != nil
    }

    /// Soll nach dieser Taste die Pause neu gemessen werden? Nicht bei Esc (der
    /// Nutzer will den Vorschlag weghaben) und nicht bei ⌘/⌃-Kurzbefehlen.
    static func restartsPause(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode != escapeKeyCode && flags.isDisjoint(with: [.maskCommand, .maskControl])
    }
}

// MARK: - Bereinigung der Modellantwort (Design §3 „Tampering der Ausgabe")

enum AutocompleteSanitizer {
    static let maxWords = 8
    static let maxCharacters = 80

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
        } else if let letter = startedSingleLetter(context),
                  body.first.map({ String($0).lowercased() == letter.lowercased() }) == true,
                  body.prefix(while: \.isLetter).count > 1,
                  !isOneLetterWord(letter, context: context) {
            // Ein angefangenes Wort aus nur einem Buchstaben („gut g" + „geht")
            // fängt `overlapLength` bewusst nicht (minOverlap 2, sonst „I have
            // pple"). Hier entscheidet die Sprache: Ist der Buchstabe dort kein
            // Wort, wird er vervollständigt statt ein neues Wort anzuhängen.
            body = String(body.dropFirst())
            completesWord = true
        }

        // 3. Anschluss an den Kontext.
        let joined = join(body, context: context, modelHadLeadingSpace: modelHadLeadingSpace,
                          completesWord: completesWord, isKnownWord: isKnownWord)

        // 4. Kürzen.
        return truncate(joined)
    }

    /// Einbuchstabige Wörter je Sprache. Deutsch hat keine — dort ist ein
    /// einzelner Buchstabe am Ende immer ein angefangenes Wort.
    static let oneLetterWords: [NLLanguage: Set<String>] = [
        .german: [], .english: ["a", "i"], .spanish: ["a", "e", "o", "u", "y"],
        .french: ["a", "y"], .italian: ["a", "e", "i", "o"], .portuguese: ["a", "e", "o"],
    ]

    /// Endet der Kontext mit genau einem Buchstaben nach einer Wortgrenze?
    static func startedSingleLetter(_ context: String) -> String? {
        guard let last = context.last, last.isLetter else { return nil }
        let before = context.dropLast().last
        guard before.map({ !$0.isLetter && !$0.isNumber }) ?? true else { return nil }
        return String(last)
    }

    /// Ist `letter` in der Sprache des Kontexts ein eigenes Wort? Unbekannte
    /// Sprache → Vereinigung aller Listen (lieber altes Verhalten als falsch
    /// zusammenkleben).
    static func isOneLetterWord(_ letter: String, context: String) -> Bool {
        let lower = letter.lowercased()
        if let language = NLLanguageRecognizer.dominantLanguage(for: context),
           let words = oneLetterWords[language] {
            return words.contains(lower)
        }
        return oneLetterWords.values.contains { $0.contains(lower) }
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
    static let maxTokens = 40
    static let temperature = 0.2
    /// Nur nicht-privilegierte Ports (Bereichsprüfung, Design §3).
    static let allowedPorts = 1024...65_535

    static let systemPrompt = """
        Setze den Text des Nutzers fort, in seiner Sprache. Gib NUR die Fortsetzung aus: \
        den Rest des aktuellen Satzes, höchstens 8 Wörter. Wiederhole den Anfang nicht. \
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
    /// Höchstens so viele eigene Wörter, je höchstens so lang — der Prompt
    /// bleibt kurz, auch bei einer langen Liste.
    static let maxGlossaryTerms = 40
    static let maxGlossaryTermLength = 40

    /// Grundprompt plus die eigenen Wörter des Nutzers als Schreibweisen-Liste.
    /// Die Begriffe sind Daten: Steuerzeichen/Zeilenumbrüche werden zu
    /// Leerzeichen, überlange und leere fallen weg.
    static func systemPrompt(glossary: [String]) -> String {
        let terms = glossary
            .map { term in
                String(term.unicodeScalars.map { $0.properties.generalCategory == .control ? " " : Character($0) })
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .filter { !$0.isEmpty && $0.count <= maxGlossaryTermLength }
            .prefix(maxGlossaryTerms)
        guard !terms.isEmpty else { return systemPrompt }
        return systemPrompt + " Schreibe diese Namen und Begriffe genau so: " + terms.joined(separator: ", ") + "."
    }

    static func make(server: URL, model: String, context: String, glossary: [String] = []) -> URLRequest? {
        guard isLoopback(server) else { return nil }
        let body = Body(
            model: model,
            messages: [Message(role: "system", content: systemPrompt(glossary: glossary)),
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

// MARK: - Wort für Wort (⇥) und Weitertippen

enum AutocompleteSuggestion {
    /// ⇥ nimmt nur das nächste Wort (samt führendem Leerzeichen und anhängender
    /// Satzzeichen); der Rest bleibt stehen. `rest == nil` = nichts mehr übrig.
    static func nextWord(of suggestion: String) -> (take: String, rest: String?) {
        let leading = suggestion.prefix { $0.isWhitespace }
        let word = suggestion.dropFirst(leading.count).prefix { !$0.isWhitespace }
        let take = String(leading + word)
        let rest = String(suggestion.dropFirst(take.count))
        return (take, rest.trimmingCharacters(in: .whitespaces).isEmpty ? nil : rest)
    }

    /// Was die gedrückte Übernahme-Taste einfügt: ein Wort oder den ganzen Rest.
    static func take(_ action: AutocompleteAcceptAction, of suggestion: String) -> (take: String, rest: String?) {
        action == .nextWord ? nextWord(of: suggestion) : (suggestion, nil)
    }

    enum TypeThrough: Equatable {
        /// Getipptes Zeichen passt — Vorschlag um dieses Zeichen kürzen.
        case keep(String)
        /// Passt, aber danach ist nichts mehr übrig.
        case usedUp
        /// Passt nicht — Vorschlag verwerfen, neu anfragen.
        case mismatch
    }

    /// „Einfach weitertippen": Tippt der Nutzer genau das nächste Zeichen des
    /// Vorschlags, bleibt der Vorschlag stehen und wird kürzer — kein Flackern,
    /// keine neue Anfrage. Groß/klein egal (Satzanfang).
    static func afterTyping(_ typed: String, suggestion: String) -> TypeThrough {
        guard typed.count == 1, let next = suggestion.first,
              typed.lowercased() == String(next).lowercased() else { return .mismatch }
        let rest = String(suggestion.dropFirst())
        return rest.trimmingCharacters(in: .whitespaces).isEmpty ? .usedUp : .keep(rest)
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

    /// Schriftgröße für den Vorschlag: die von der App gemeldete Schriftgröße
    /// des Zeichens vor dem Cursor, wenn es eine gibt und sie zur Zeilenhöhe am
    /// Bildschirm passt — sonst die Schätzung aus der Zeilenhöhe. Bei Zoom
    /// (Pages auf 200 %) meldet die App Dokument-Punkte, nicht Bildschirm-Punkte;
    /// dann passt die Zahl nicht zur Cursorhöhe und wird verworfen.
    static func fontSize(reported: CGFloat?, caretHeight: CGFloat) -> CGFloat {
        guard let reported, reported >= caretHeight * 0.5, reported <= caretHeight else {
            return fontSize(forCaretHeight: caretHeight)
        }
        return min(max(reported, 11), 28)
    }
}
