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
        case uppercase
        case lowercase
        case capitalizeWords
        case underscore
        case splitUnderscore
        case slugify
        case hyphenate
        case transliterateUmlauts
        case brackets
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

    static var all: [LocalTextAction] {
        [
            LocalTextAction(kind: .bold, title: String(localized: "local.action.bold"), symbol: "bold", category: .formatting),
            LocalTextAction(kind: .italic, title: String(localized: "local.action.italic"), symbol: "italic", category: .formatting),
            LocalTextAction(kind: .underline, title: String(localized: "local.action.underline"), symbol: "underline", category: .formatting),
            LocalTextAction(kind: .strikethrough, title: String(localized: "local.action.strikethrough"), symbol: "strikethrough", category: .formatting),
            LocalTextAction(kind: .uppercase, title: String(localized: "local.action.uppercase"), label: "AA", category: .transform),
            LocalTextAction(kind: .lowercase, title: String(localized: "local.action.lowercase"), label: "aa", category: .transform),
            LocalTextAction(kind: .capitalizeWords, title: String(localized: "local.action.capitalizeWords"), label: "Aa", category: .transform),
            LocalTextAction(kind: .underscore, title: String(localized: "local.action.underscore"), label: "A_b", category: .transform),
            LocalTextAction(kind: .slugify, title: String(localized: "local.action.slugify"), label: "a_b", category: .transform),
            LocalTextAction(kind: .splitUnderscore, title: String(localized: "local.action.splitUnderscore"), label: "A b", category: .transform),
            LocalTextAction(kind: .hyphenate, title: String(localized: "local.action.hyphenate"), label: "A-b", category: .transform),
            LocalTextAction(kind: .transliterateUmlauts, title: String(localized: "local.action.transliterateUmlauts"), label: "äöü", category: .transform),
            LocalTextAction(kind: .brackets, title: String(localized: "local.action.brackets"), symbol: "parentheses", category: .transform),
            LocalTextAction(kind: .joinLines, title: String(localized: "local.action.joinLines"), symbol: "text.append", category: .transform),
            LocalTextAction(kind: .characterCount, title: String(localized: "local.action.characterCount"), symbol: "number", category: .info),
            LocalTextAction(kind: .wordCount, title: String(localized: "local.action.wordCount"), symbol: "text.word.spacing", category: .info),
        ]
    }

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
        }

        return attributed
    }
}
