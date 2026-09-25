import Foundation

/// Pronunciation variants inside the custom-words list: `Tipi → Tippi`.
///
/// Real case, 2026-09-25: Michael says "Tippi", Parakeet writes "Tipi". The
/// glossary in the AI cleanup prompt cannot fix that, on purpose — "Tipi" is a
/// real word, and the prompt forbids the model to turn one real word into
/// another ("never alter any other word to resemble them"). That rule stays.
/// Parakeet itself takes no word list. So the correction has to be explicit and
/// deterministic: the user states which heard word means which intended word,
/// and Tippi swaps exactly that, nothing it has to guess.
///
/// Storage stays the plain `[String]` of `DictationSettings.customWords` (synced
/// via `SyncedPreferences`): an entry with an arrow is a rule, an entry without
/// one is a glossary term as before. No migration, and an older Tippi on the
/// other Mac simply sees one more glossary term.
enum CustomWordVariants {
    /// One `heard, heard → target` entry.
    struct Rule: Equatable {
        let variants: [String]
        let target: String
    }

    /// What a single stored entry means.
    enum Entry: Equatable {
        /// Plain term — glossary only, as before.
        case term(String)
        /// Heard variants → intended spelling.
        case rule(Rule)
    }

    /// Accepted arrows. `→` is what the UI shows; `->` and `=>` because nobody
    /// types `→` on a German keyboard.
    static let arrows = ["→", "->", "=>"]

    /// Parses one stored entry. `nil` = nothing usable (empty, or an arrow with
    /// no target on the right).
    ///
    /// - `Tipi → Tippi` → rule
    /// - `Tipi, Tippie -> Tippi` → rule with two variants
    /// - `→ Tippi` (nothing on the left) → plain term `Tippi`
    /// - `Tipi →` (nothing on the right) → `nil`: there is no spelling to enforce
    /// - `CINEWEB` → plain term
    static func parse(_ entry: String) -> Entry? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Split at the earliest arrow, whichever kind it is.
        let firstArrow = arrows
            .compactMap { trimmed.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
        guard let arrow = firstArrow else { return .term(trimmed) }

        let target = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        let variants = trimmed[..<arrow.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != target }
        guard !variants.isEmpty else { return .term(target) }
        return .rule(Rule(variants: variants, target: target))
    }

    /// All rules in the list, in list order.
    static func rules(from entries: [String]) -> [Rule] {
        entries.compactMap { entry in
            if case .rule(let rule) = parse(entry) { return rule }
            return nil
        }
    }

    /// The terms the AI cleanup glossary gets: plain entries plus the *targets*
    /// of rules — never the variants. Naming "Tipi" to the model would invite
    /// exactly the guessing the strict prompt rule exists to prevent.
    /// De-duplicated, list order kept.
    static func glossaryTerms(from entries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            let term: String
            switch parse(entry) {
            case .term(let plain): term = plain
            case .rule(let rule): term = rule.target
            case nil: continue
            }
            if seen.insert(term).inserted { result.append(term) }
        }
        return result
    }

    /// Replaces every heard variant in `text` by its target.
    ///
    /// Whole words only, case-insensitive, Unicode-aware: a letter, combining
    /// mark or digit directly before or after blocks the match, so "Tipis" and
    /// "Stipi" stay untouched while "Tipi," becomes "Tippi,". The target is
    /// inserted exactly as written.
    ///
    /// One pass with one alternation, longest variant first — so a multi-word
    /// variant beats its own first word, and a replacement can never be picked
    /// up again by another rule (`A → B`, `B → C` does not chain to C).
    static func apply(to text: String, entries: [String]) -> String {
        let rules = rules(from: entries)
        guard !rules.isEmpty, !text.isEmpty else { return text }

        var pairs: [(variant: String, target: String)] = []
        for rule in rules {
            for variant in rule.variants { pairs.append((variant, rule.target)) }
        }
        // Stable sort: equal lengths keep list order, so the first rule wins.
        let ordered = pairs.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (lhs.element.variant.count, rhs.element.variant.count)
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map(\.element)

        let wordChar = "[\\p{L}\\p{M}\\p{N}]"
        let groups = ordered
            .map { "(" + NSRegularExpression.escapedPattern(for: $0.variant) + ")" }
            .joined(separator: "|")
        let pattern = "(?<!\(wordChar))(?:\(groups))(?!\(wordChar))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            // Group n+1 belongs to ordered[n]; exactly one of them took part.
            guard let index = (1..<match.numberOfRanges).first(where: {
                match.range(at: $0).location != NSNotFound
            }) else { continue }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += ordered[index - 1].target
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }
}
