import AppKit
import Foundation

enum LocalQuickActionSettings {
    static let showActionsKey = "localQuickActions.enabled"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: showActionsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: showActionsKey)
    }
}

enum LocalTextActionCategory {
    case formatting
    /// Wraps the selection in a pair of delimiters — brackets, quotes.
    case enclose
    case transform
    case info
}

enum LocalTextActionResult {
    case plainReplacement(String)
    case richReplacement(attributed: NSAttributedString, fallback: String)
    case info(String)
}

struct LocalTextAction: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case bold
        case italic
        case underline
        case strikethrough
        case highlight
        case bulletList
        case quotes
        case uppercase
        case lowercase
        case capitalizeWords
        case underscore
        case splitUnderscore
        case slugify
        case hyphenate
        case transliterateUmlauts
        case brackets
        case squareBrackets
        case curlyBraces
        case joinLines
        case characterCount
        case wordCount
    }

    let kind: Kind
    let title: String
    /// SF Symbol name. Empty when `label` carries the button instead.
    let symbol: String
    /// Typographic label shown *instead of* an icon.
    ///
    /// Case and separator transforms are about letterforms, so a pictogram has
    /// to encode something the glyphs already say better. Two real failures on
    /// 2026-09-14: the `underscore` SF Symbol does not exist at all, so that
    /// button rendered blank and was clicked past for weeks, and `textformat`
    /// renders as "Aa" for *lowercase*, which reads as the opposite. `AA` /
    /// `aa` / `A_B` need no legend.
    let label: String?
    let category: LocalTextActionCategory

    var id: String { kind.rawValue }

    init(kind: Kind, title: String, symbol: String = "", label: String? = nil,
         category: LocalTextActionCategory) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.label = label
        self.category = category
    }

    // `text.append` for "join lines" looked like "insert a line break" — the
    // opposite — and `text.word.spacing` was just stripes; both became text
    // labels on 2026-09-28 (Michael: "aussagekräftige Icons").
    // Eine Aktion pro Zeile, als Tabelle lesbar — umbrechen würde das zerreißen.
    // swiftlint:disable line_length
    static var all: [LocalTextAction] {
        [
            LocalTextAction(kind: .bold, title: String(localized: "local.action.bold"), symbol: "bold", category: .formatting),
            LocalTextAction(kind: .italic, title: String(localized: "local.action.italic"), symbol: "italic", category: .formatting),
            LocalTextAction(kind: .underline, title: String(localized: "local.action.underline"), symbol: "underline", category: .formatting),
            LocalTextAction(kind: .strikethrough, title: String(localized: "local.action.strikethrough"), symbol: "strikethrough", category: .formatting),
            LocalTextAction(kind: .highlight, title: String(localized: "local.action.highlight"), symbol: "highlighter", category: .formatting),
            LocalTextAction(kind: .bulletList, title: String(localized: "local.action.bulletList"), symbol: "list.bullet", category: .formatting),
            // Enclosing pairs show the pair itself: `( ) [ ] { }` say exactly
            // what will happen, and `square.brackets` is not an SF Symbol.
            LocalTextAction(kind: .quotes, title: String(localized: "local.action.quotes"), label: LocalTextTransformer.quoteDelimiters.open + " " + LocalTextTransformer.quoteDelimiters.close, category: .enclose),
            LocalTextAction(kind: .brackets, title: String(localized: "local.action.brackets"), label: "( )", category: .enclose),
            LocalTextAction(kind: .squareBrackets, title: String(localized: "local.action.squareBrackets"), label: "[ ]", category: .enclose),
            LocalTextAction(kind: .curlyBraces, title: String(localized: "local.action.curlyBraces"), label: "{ }", category: .enclose),
            LocalTextAction(kind: .uppercase, title: String(localized: "local.action.uppercase"), label: "AA", category: .transform),
            LocalTextAction(kind: .lowercase, title: String(localized: "local.action.lowercase"), label: "aa", category: .transform),
            LocalTextAction(kind: .capitalizeWords, title: String(localized: "local.action.capitalizeWords"), label: "Aa", category: .transform),
            LocalTextAction(kind: .underscore, title: String(localized: "local.action.underscore"), label: "A_b", category: .transform),
            LocalTextAction(kind: .slugify, title: String(localized: "local.action.slugify"), label: "a_b", category: .transform),
            LocalTextAction(kind: .splitUnderscore, title: String(localized: "local.action.splitUnderscore"), label: "A b", category: .transform),
            LocalTextAction(kind: .hyphenate, title: String(localized: "local.action.hyphenate"), label: "A-b", category: .transform),
            LocalTextAction(kind: .transliterateUmlauts, title: String(localized: "local.action.transliterateUmlauts"), label: "äöü", category: .transform),
            LocalTextAction(kind: .joinLines, title: String(localized: "local.action.joinLines"), label: "¶→␣", category: .transform),
            LocalTextAction(kind: .characterCount, title: String(localized: "local.action.characterCount"), symbol: "number", category: .info),
            LocalTextAction(kind: .wordCount, title: String(localized: "local.action.wordCount"), label: "123w", category: .info),
        ]
    }
    // swiftlint:enable line_length

    func perform(on text: String) -> LocalTextActionResult {
        switch kind {
        case .bold:
            return .richReplacement(
                attributed: RichTextFormatter.apply(.bold, to: text),
                fallback: "**\(text)**"
            )
        case .italic:
            return .richReplacement(
                attributed: RichTextFormatter.apply(.italic, to: text),
                fallback: "_\(text)_"
            )
        case .underline:
            return .richReplacement(
                attributed: RichTextFormatter.apply(.underline, to: text),
                fallback: "<u>\(text)</u>"
            )
        case .strikethrough:
            return .richReplacement(
                attributed: RichTextFormatter.apply(.strikethrough, to: text),
                fallback: "~~\(text)~~"
            )
        case .highlight:
            // No plain-text fallback on purpose (Michael, 2026-09-28): an app
            // without formatting simply gets the text back unchanged.
            // `ReplacementWriter` routes a formatting-only change straight to
            // the rich paste, so the unchanged plain text is never mistaken for
            // an ignored write.
            return .richReplacement(
                attributed: RichTextFormatter.apply(.highlight, to: text),
                fallback: text
            )
        case .bulletList:
            return .plainReplacement(LocalTextTransformer.bulletList(text))
        case .quotes:
            return .plainReplacement(LocalTextTransformer.quotes(text))
        case .uppercase:
            return .plainReplacement(LocalTextTransformer.uppercase(text))
        case .lowercase:
            return .plainReplacement(LocalTextTransformer.lowercase(text))
        case .capitalizeWords:
            return .plainReplacement(LocalTextTransformer.capitalizeWords(text))
        case .underscore:
            return .plainReplacement(LocalTextTransformer.underscore(text))
        case .splitUnderscore:
            return .plainReplacement(LocalTextTransformer.splitUnderscore(text))
        case .slugify:
            return .plainReplacement(LocalTextTransformer.slugify(text))
        case .hyphenate:
            return .plainReplacement(LocalTextTransformer.hyphenate(text))
        case .transliterateUmlauts:
            return .plainReplacement(LocalTextTransformer.transliterateUmlauts(text))
        case .brackets:
            return .plainReplacement(LocalTextTransformer.brackets(text))
        case .squareBrackets:
            return .plainReplacement(LocalTextTransformer.squareBrackets(text))
        case .curlyBraces:
            return .plainReplacement(LocalTextTransformer.curlyBraces(text))
        case .joinLines:
            return .plainReplacement(LocalTextTransformer.joinLines(text))
        case .characterCount:
            return .info(String(format: String(localized: "local.action.characterCount.result"), text.count))
        case .wordCount:
            return .info(String(format: String(localized: "local.action.wordCount.result"), LocalTextTransformer.wordCount(text)))
        }
    }
}

enum LocalTextTransformer {
    static func uppercase(_ text: String) -> String {
        text.uppercased()
    }

    static func lowercase(_ text: String) -> String {
        text.lowercased()
    }

    static func capitalizeWords(_ text: String) -> String {
        text.localizedCapitalized
    }

    /// German-to-ASCII transliteration for filenames, URLs, and identifiers
    /// — the exact mapping the vault's own file-naming convention already
    /// uses (ä→ae, ö→oe, ü→ue, ß→ss), case-preserving. Everything else is
    /// left untouched; this is character substitution, not a full slugify
    /// (no space/punctuation stripping) — that's what `underscore`/
    /// `hyphenate` already do, and now do correctly instead of leaving raw
    /// umlauts in an otherwise "web-safe" identifier.
    static func transliterateUmlauts(_ text: String) -> String {
        let map: [(String, String)] = [
            ("ä", "ae"), ("ö", "oe"), ("ü", "ue"),
            ("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"),
            ("ß", "ss"),
        ]
        return map.reduce(text) { partial, pair in
            partial.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    static func underscore(_ text: String) -> String {
        words(in: transliterateUmlauts(text)).joined(separator: "_")
    }

    /// Inverse of `underscore`: `hallo_welt` → `hallo welt`.
    ///
    /// Deliberately not routed through `words(in:)` like its counterpart.
    /// Word enumeration would also split on every other boundary, so
    /// `snake_case.and.dots` would lose its dots too — but the user asked for
    /// underscores back, nothing else. Line breaks survive for the same
    /// reason: a multi-line selection keeps its shape.
    static func splitUnderscore(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line -> String in
                line
                    .replacingOccurrences(of: "_", with: " ")
                    // `a__b` would otherwise become `a  b`. Collapse runs of
                    // spaces the replacement itself produced, without touching
                    // the user's own indentation at the start of the line.
                    .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            }
            .joined(separator: "\n")
    }

    /// Lowercase plus underscores in one step: `Wichtig ist nur` →
    /// `wichtig_ist_nur`. The combination people actually want for file names
    /// and identifiers, which previously took two clicks in the right order.
    static func slugify(_ text: String) -> String {
        underscore(text).lowercased()
    }

    static func hyphenate(_ text: String) -> String {
        words(in: transliterateUmlauts(text)).joined(separator: "-")
    }

    static func brackets(_ text: String) -> String {
        "(\(text))"
    }

    static func squareBrackets(_ text: String) -> String {
        "[\(text)]"
    }

    static func curlyBraces(_ text: String) -> String {
        "{\(text)}"
    }

    /// The system's quotation marks — „…“ on a German Mac, “…” on an English
    /// one — so the button matches what the user would type by hand.
    static var quoteDelimiters: (open: String, close: String) {
        (Locale.current.quotationBeginDelimiter ?? "\u{201E}",
         Locale.current.quotationEndDelimiter ?? "\u{201C}")
    }

    static func quotes(_ text: String) -> String {
        quoteDelimiters.open + text + quoteDelimiters.close
    }

    /// Markdown bullet list: `- ` before every non-empty line, after its
    /// indentation. Lines that already start with `- ` are left alone, so a
    /// second click does not produce `- - `.
    static func bulletList(_ text: String) -> String {
        // Split on `Character.isNewline`: `\r\n` is one Character, so CRLF
        // text does not gain empty lines the way `components(separatedBy:)`
        // would produce them.
        text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line -> String in
                let body = line.drop { $0 == " " || $0 == "\t" }
                guard !body.isEmpty, !body.hasPrefix("- ") else { return String(line) }
                let indent = line.prefix(line.count - body.count)
                return indent + "- " + body
            }
            .joined(separator: "\n")
    }

    static func joinLines(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func words(in text: String) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) { substring, _, _, _ in
            if let substring {
                words.append(String(substring))
            }
        }
        return words
    }
}

enum RichTextFormatter {
    enum Style {
        case bold
        case italic
        case underline
        case strikethrough
        case highlight
    }

    static func apply(_ style: Style, to text: String) -> NSAttributedString {
        let range = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(string: text)

        switch style {
        case .bold:
            attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), range: range)
        case .italic:
            let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize), toHaveTrait: .italicFontMask)
            attributed.addAttribute(.font, value: font, range: range)
        case .underline:
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .strikethrough:
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .highlight:
            // Plain yellow, the colour Mail, Pages and TextEdit use for their
            // own highlighter — a dynamic system colour would not survive RTF.
            attributed.addAttribute(.backgroundColor, value: NSColor.yellow, range: range)
            // Fixed dark text on the yellow, so the text does not inherit a
            // dynamic white in Dark Mode. Measured 2026-09-28: TextEdit's
            // "dark background for windows" still lightens *every* dark text
            // colour (black and #1A1A1A alike) for display only — the stored
            // colour is right and shows dark as soon as that option is off.
            // Nothing Tippi can influence; background colours are kept.
            attributed.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        }

        return attributed
    }
}
