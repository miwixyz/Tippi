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
        case hyphenate
        case brackets
        case joinLines
        case characterCount
        case wordCount
    }

    let kind: Kind
    let title: String
    let symbol: String
    let category: LocalTextActionCategory

    var id: String { kind.rawValue }

    static var all: [LocalTextAction] {
        [
            LocalTextAction(kind: .bold, title: String(localized: "local.action.bold"), symbol: "bold", category: .formatting),
            LocalTextAction(kind: .italic, title: String(localized: "local.action.italic"), symbol: "italic", category: .formatting),
            LocalTextAction(kind: .underline, title: String(localized: "local.action.underline"), symbol: "underline", category: .formatting),
            LocalTextAction(kind: .strikethrough, title: String(localized: "local.action.strikethrough"), symbol: "strikethrough", category: .formatting),
            LocalTextAction(kind: .uppercase, title: String(localized: "local.action.uppercase"), symbol: "textformat", category: .transform),
            LocalTextAction(kind: .lowercase, title: String(localized: "local.action.lowercase"), symbol: "textformat", category: .transform),
            LocalTextAction(kind: .capitalizeWords, title: String(localized: "local.action.capitalizeWords"), symbol: "textformat.abc", category: .transform),
            LocalTextAction(kind: .underscore, title: String(localized: "local.action.underscore"), symbol: "underscore", category: .transform),
            LocalTextAction(kind: .hyphenate, title: String(localized: "local.action.hyphenate"), symbol: "minus", category: .transform),
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
        case .hyphenate:
            return .plainReplacement(LocalTextTransformer.hyphenate(text))
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

    static func underscore(_ text: String) -> String {
        words(in: text).joined(separator: "_")
    }

    static func hyphenate(_ text: String) -> String {
        words(in: text).joined(separator: "-")
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
