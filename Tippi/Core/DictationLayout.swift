import Foundation
import NaturalLanguage

/// „Absätze und Satzzeichen setzen (z. B. für Mails)" — Diktat-Option, ab Werk aus.
///
/// Rein regelbasiert, ohne KI: läuft nach der KI-Glättung oder allein, wenn die aus
/// ist. Anrede in eine eigene Zeile, jeder Satz eine Zeile, Grußformel mit Leerzeile
/// davor, Doppelpunkt vor „folgende …". Ein einzelner Satz ohne Grußformel bleibt,
/// wie er ist (bis auf den Doppelpunkt) — Chat-Nachrichten werden nicht zerlegt.
///
/// Warum keine KI (gemessen 2026-09-30): Gemma 4 E2B ignorierte den Layout-Zusatz im
/// Prompt in Michaels echtem Test ganz; mit Beispiel-Grußformeln im Prompt hängte es
/// dafür „Best regards" an Notizen an (Wortlaut in 18 von 30 Antworten verändert).
/// Which hot key started the dictation.
enum DictationSource: Equatable {
    /// ⌃⌥⌘M (or the single key): layout only with the switch on.
    case standard
    /// „Diktat für Mails": layout always.
    case mail
}

enum DictationLayout {
    /// Layout or not. Never in terminals and apps on the „Enter nach dem Diktat" list
    /// (`targetIsTerminal`): a line break there can send a command or a message.
    static func layoutWanted(source: DictationSource, toggle: Bool, targetIsTerminal: Bool) -> Bool {
        guard !targetIsTerminal else { return false }
        return source == .mail || toggle
    }

    /// Anrede bis zum ersten Komma, höchstens so viele Wörter („Sehr geehrte Frau Dr. Müller,").
    static let maxSalutationWords = 6
    /// Ein letzter Satz mit Grußwort zählt nur bis zu dieser Länge als Grußformel.
    static let maxClosingWords = 8

    /// Anrede-Anfänge (klein geschrieben, als Wortfolge).
    static let salutations: [[String]] = [
        ["hallo"], ["hi"], ["hey"], ["moin"], ["servus"], ["grüß", "gott"], ["guten", "morgen"],
        ["guten", "tag"], ["guten", "abend"], ["sehr", "geehrte"], ["sehr", "geehrter"], ["sehr", "geehrtes"],
        ["liebe"], ["lieber"], ["liebes"], ["hello"], ["dear"], ["good", "morning"], ["hola"],
        ["buenos", "días"], ["buenas", "tardes"], ["querida"], ["querido"], ["estimada"], ["estimado"],
    ]
    /// Bei diesen Anfängen muss ein großgeschriebenes Wort folgen („Liebe Anna,"),
    /// sonst wäre „Liebe ist alles, was zählt." eine Anrede.
    static let salutationsNeedingName: Set<String> = ["liebe", "lieber", "liebes", "dear", "querida",
                                                      "querido", "estimada", "estimado"]

    /// Grußwörter; eines davon im (kurzen) letzten Satz macht ihn zur Grußformel,
    /// auch eingebettet („Vielen Dank und liebe Grüße", „Danke und viele Grüße aus München").
    static let closingWords: [[String]] = [
        ["grüße"], ["grüsse"], ["gruß"], ["gruss"], ["grüßen"], ["grüssen"], ["grüßle"],
        ["lg"], ["vg"], ["mfg"], ["regards"], ["cheers"], ["sincerely"], ["best", "wishes"],
        ["thanks", "and", "best"], ["saludos"], ["saludo"], ["abrazo"], ["atentamente"], ["cordialmente"],
    ]

    /// Aus einem Satz, der auf „." endet und das ankündigt, wird ein Doppelpunkt.
    static let announcements: [[String]] = [
        ["folgende"], ["folgenden"], ["folgendes"], ["folgender"], ["wie", "folgt"],
        ["following"], ["as", "follows"], ["lo", "siguiente"],
    ]

    /// Abkürzungen, nach denen `NLTokenizer` fälschlich einen Satz beendet (gemessen:
    /// „Prof." und „ca." trennte er, „z. B." und „Dr." am Satzanfang nicht immer).
    static let abbreviations: Set<String> = [
        "dr.", "prof.", "nr.", "ca.", "bzw.", "vgl.", "ggf.", "evtl.", "inkl.", "zzgl.", "hr.", "fr.",
        "st.", "str.", "tel.", "mio.", "mrd.", "z.b.", "u.a.", "d.h.", "mr.", "mrs.", "ms.", "e.g.",
        "i.e.", "vs.", "sr.", "sra.",
    ]

    static func format(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = sentences(in: trimmed).map(withColon)
        guard lines.count > 1 else {
            let single = lines.first ?? trimmed
            return single == trimmed ? text : single
        }
        var closing: String?
        if let last = lines.last, isClosing(last) { closing = lines.removeLast() }
        var salutation: String?
        if let first = lines.first, let split = splitSalutation(first) {
            salutation = split.salutation
            lines[0] = split.rest
        }
        let body = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        return [salutation, body.isEmpty ? nil : body, closing].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// Sätze über `NLTokenizer`, Fehltrennungen nach Ordnungszahlen („am 3. Oktober"),
    /// Einzelbuchstaben („S. 4") und `abbreviations` wieder zusammengefügt.
    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        var merge = false
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let piece = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { return true }
            if merge, let last = result.popLast() {
                result.append(last + " " + piece)
            } else {
                result.append(piece)
            }
            merge = endsWithAbbreviation(result.last ?? "")
            return true
        }
        return result
    }

    static func endsWithAbbreviation(_ sentence: String) -> Bool {
        guard let last = sentence.split(whereSeparator: \.isWhitespace).last, last.hasSuffix(".") else { return false }
        let core = last.dropLast()
        if (1...2).contains(core.count), core.allSatisfy(\.isNumber) { return true }   // „3."
        if core.count == 1, core.first?.isLetter == true { return true }              // „S.", „B."
        return abbreviations.contains(last.lowercased())
    }

    static func withColon(_ sentence: String) -> String {
        guard sentence.hasSuffix("."), !sentence.hasSuffix(".."),
              contains(announcements, in: words(sentence)) else { return sentence }
        return String(sentence.dropLast()) + ":"
    }

    static func isClosing(_ sentence: String) -> Bool {
        let sentenceWords = words(sentence)
        return sentenceWords.count <= maxClosingWords && contains(closingWords, in: sentenceWords)
    }

    /// „Hallo lieber Mensch, ich möchte …" → („Hallo lieber Mensch,", „ich möchte …").
    /// Die Groß-/Kleinschreibung des Rests bleibt (deutsche Briefkonvention: klein weiter).
    static func splitSalutation(_ sentence: String) -> (salutation: String, rest: String)? {
        guard let comma = sentence.firstIndex(of: ",") else { return nil }
        let head = String(sentence[...comma])
        let headWords = words(head)
        guard headWords.count <= maxSalutationWords,
              let starter = salutations.first(where: { headWords.starts(with: $0) }) else { return nil }
        if salutationsNeedingName.contains(starter[0]) {
            let original = head.split { !$0.isLetter }
            guard original.count > 1, original[1].first?.isUppercase == true else { return nil }
        }
        let rest = sentence[sentence.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return (head, rest)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func contains(_ phrases: [[String]], in sentenceWords: [String]) -> Bool {
        phrases.contains { phrase in
            sentenceWords.count >= phrase.count && (0...(sentenceWords.count - phrase.count)).contains {
                Array(sentenceWords[$0..<($0 + phrase.count)]) == phrase
            }
        }
    }
}
