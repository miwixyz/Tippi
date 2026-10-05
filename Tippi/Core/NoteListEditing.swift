import Foundation

/// Plain-text lists for the Notes editor: bullets (`- `), checklists (`- [ ] ` /
/// `- [x] `) and numbered lists (`1. `). Notes stay plain `.txt` files, so a list
/// is nothing but its line prefix — Markdown syntax on purpose, because TippAI
/// opens the same files and renders exactly these prefixes as lists.
///
/// Everything here is pure string logic so it can be tested without a text view;
/// `PlainTextEditor` only decides *when* to call it (Return, toolbar, click).
/// "Optional" in the sense Michael chose (2026-10-05): nothing happens unless a
/// line already is a list item or he presses a list button.
enum NoteListEditing {

    enum Kind: Equatable {
        case bullet
        case checklist
        case numbered
    }

    /// A line recognised as a list item.
    struct Item: Equatable {
        /// Leading spaces/tabs, kept when the list continues.
        let indent: String
        let kind: Kind
        /// Only for `.numbered`.
        let number: Int?
        /// Only for `.checklist`.
        let checked: Bool
        /// Full prefix including indent, e.g. `"  - [ ] "` — UTF-16 length is
        /// what NSTextView ranges need.
        let prefix: String
        /// Text after the prefix.
        let content: String
    }

    // MARK: Parsing

    static func parse(_ line: String) -> Item? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)

        // Checklist before bullet: "- [ ] " also starts with "- ".
        for (marker, checked) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)]
        where rest.hasPrefix(marker) {
            return Item(indent: indent, kind: .checklist, number: nil, checked: checked,
                        prefix: indent + marker, content: String(rest.dropFirst(marker.count)))
        }
        for marker in ["- ", "* ", "• "] where rest.hasPrefix(marker) {
            return Item(indent: indent, kind: .bullet, number: nil, checked: false,
                        prefix: indent + marker, content: String(rest.dropFirst(marker.count)))
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 4, let number = Int(digits) {
            let afterDigits = rest.dropFirst(digits.count)
            for separator in [". ", ") "] where afterDigits.hasPrefix(separator) {
                let marker = String(digits) + separator
                return Item(indent: indent, kind: .numbered, number: number, checked: false,
                            prefix: indent + marker, content: String(afterDigits.dropFirst(separator.count)))
            }
        }
        return nil
    }

    // MARK: Return key

    enum Continuation: Equatable {
        /// Not a list line — Return behaves normally.
        case none
        /// Insert a line break followed by this prefix.
        case continueWith(String)
        /// The item is empty: remove its prefix and stop the list (no new line).
        case endList(prefixLength: Int)
    }

    /// What Return should do at the end of `line` (the text before the cursor on
    /// that line). Checklists continue unchecked; numbers count up; the separator
    /// (`.` or `)`) and the indent are kept.
    static func continuation(forLineBeforeCursor line: String) -> Continuation {
        guard let item = parse(line) else { return .none }
        if item.content.trimmingCharacters(in: .whitespaces).isEmpty {
            return .endList(prefixLength: (item.prefix as NSString).length)
        }
        switch item.kind {
        case .bullet:
            return .continueWith(item.prefix)
        case .checklist:
            return .continueWith(item.indent + "- [ ] ")
        case .numbered:
            let separator = item.prefix.hasSuffix(") ") ? ") " : ". "
            return .continueWith(item.indent + String((item.number ?? 0) + 1) + separator)
        }
    }

    // MARK: Toolbar

    /// Turns `lines` into a list of `kind`, or back into plain text when every
    /// non-empty line already is that kind (second press = undo the list).
    /// Empty lines stay empty; numbering restarts at 1 for the block; an item of
    /// another kind is converted, not double-prefixed.
    static func toggle(_ kind: Kind, lines: [String]) -> [String] {
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Cursor on an empty line: start a list there instead of doing nothing.
        if nonEmpty.isEmpty, lines.count == 1 {
            let indent = lines[0]
            switch kind {
            case .bullet: return [indent + "- "]
            case .checklist: return [indent + "- [ ] "]
            case .numbered: return [indent + "1. "]
            }
        }
        let alreadyAll = !nonEmpty.isEmpty && nonEmpty.allSatisfy { parse($0)?.kind == kind }

        var number = 0
        return lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            let item = parse(line)
            let indent = item?.indent ?? String(line.prefix { $0 == " " || $0 == "\t" })
            let content = item?.content ?? String(line.dropFirst(indent.count))
            if alreadyAll { return indent + content }
            switch kind {
            case .bullet:
                return indent + "- " + content
            case .checklist:
                let checked = item?.kind == .checklist && item?.checked == true
                return indent + (checked ? "- [x] " : "- [ ] ") + content
            case .numbered:
                number += 1
                return indent + "\(number). " + content
            }
        }
    }

    // MARK: Checkbox click

    /// UTF-16 range of the `[ ]` / `[x]` box inside `line`, or nil when the line
    /// is not a checklist item. Clicking inside this range toggles the box.
    static func checkboxRange(in line: String) -> NSRange? {
        guard let item = parse(line), item.kind == .checklist else { return nil }
        // Prefix is indent + "- [ ] "; the box starts after indent + "- ".
        let start = (item.indent as NSString).length + 2
        return NSRange(location: start, length: 3)
    }

    /// The box text after toggling: `"[x]"` for an unchecked item, `"[ ]"` for a
    /// checked one. Nil when the line is not a checklist item.
    static func toggledCheckbox(in line: String) -> String? {
        guard let item = parse(line), item.kind == .checklist else { return nil }
        return item.checked ? "[ ]" : "[x]"
    }
}
