import Foundation
import os

private let emojiLog = Logger(subsystem: "com.tippi.app", category: "emoji")

/// One emoji with its German and English name plus search keywords, as
/// generated from Unicode CLDR by `scripts/generate-emoji-data.py`.
/// The single-letter coding keys keep the shipped JSON at ~326 KB instead of
/// ~450 KB — worth it for a file parsed on every launch.
struct Emoji: Decodable, Identifiable, Hashable {
    let character: String
    let nameDE: String
    let nameEN: String
    let keywords: [String]

    var id: String { character }

    private enum CodingKeys: String, CodingKey {
        case character = "c"
        case nameDE = "n"
        case nameEN = "e"
        case keywords = "k"
    }
}

private struct EmojiDataFile: Decodable {
    let cldrVersion: String
    let emojiVersion: String
    let count: Int
    /// Hand-pinned `:name:` shortcuts from the generator, for everyday words
    /// where "first keyword match wins" lands somewhere surprising
    /// (":daumen:" would otherwise resolve to 🫰, ":herz:" to a playing-card
    /// heart). Highest priority in the lookup table.
    let aliases: [String: String]
    let emoji: [Emoji]
}

/// Loads the CLDR emoji set and answers the two questions the UI asks:
/// "which emoji is exactly called `:rakete:`" (inline expansion, O(1)) and
/// "what matches what the user is typing" (picker search, ranked).
///
/// `@MainActor` on purpose rather than a lock: both callers — the keystroke
/// monitor and the picker panel — already run on the main actor, so isolating
/// here removes the possibility of a data race by construction instead of
/// guarding against one. The expensive part (JSON decode) still happens off
/// the main thread inside `load()`.
@MainActor
final class EmojiDatabase: ObservableObject {
    static let shared = EmojiDatabase()

    @Published private(set) var isLoaded = false
    private(set) var all: [Emoji] = []

    /// Alias → emoji for `:name:` inline expansion.
    private var aliases: [String: Emoji] = [:]

    private var isLoading = false

    private init() {}

    // MARK: - Loading

    /// Idempotent. Decodes off the main thread, publishes on it.
    /// Safe to call repeatedly (app launch, settings open, first hotkey press).
    func load() {
        guard !isLoaded, !isLoading else { return }
        isLoading = true

        Task {
            let decoded = await Self.decodeInBackground()
            self.isLoading = false
            guard let decoded else { return }
            self.all = decoded.emoji
            self.aliases = Self.buildAliases(from: decoded.emoji, curated: decoded.aliases)
            self.isLoaded = true
            emojiLog.notice("emoji database loaded — \(decoded.count) emoji, Emoji \(decoded.emojiVersion), CLDR \(decoded.cldrVersion), \(self.aliases.count) aliases")
        }
    }

    private static func decodeInBackground() async -> EmojiDataFile? {
        await Task.detached(priority: .utility) { () -> EmojiDataFile? in
            guard let url = Bundle.main.url(forResource: "emoji-data", withExtension: "json") else {
                // Not silent: a missing resource means the picker and every
                // `:name:` expansion are dead, and the user would otherwise
                // just experience "nothing happens".
                emojiLog.error("emoji-data.json missing from bundle — emoji features unavailable")
                return nil
            }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(EmojiDataFile.self, from: data)
            } catch {
                emojiLog.error("emoji-data.json could not be decoded: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    /// Shortest keyword accepted as an inline `:name:` shortcut.
    ///
    /// Two-letter keywords are real in CLDR ("ab", "an", "as", "at") and would
    /// make `:an:` — an ordinary German word — insert a mathematical symbol
    /// mid-sentence. Primary names and curated aliases are exempt: they are
    /// deliberate, not incidental.
    private static let minKeywordAliasLength = 3

    /// Builds the `:name:` lookup table, highest priority first:
    ///
    /// 1. curated aliases — hand-picked, must win (`:herz:` → ❤️)
    /// 2. German primary name, then English primary name
    /// 3. single-word keywords of at least `minKeywordAliasLength` characters
    ///
    /// Without that order a keyword like "film" could take the slot from an
    /// emoji actually *named* film. Within one tier, file order decides, and
    /// that order is canonical Unicode grouping — so a common face wins over
    /// an obscure symbol rather than it being arbitrary.
    ///
    /// Multi-word keywords are skipped entirely; `:in_ordnung:` is not
    /// something anyone types. They stay reachable through the picker search.
    private static func buildAliases(
        from emoji: [Emoji],
        curated: [String: String]
    ) -> [String: Emoji] {
        var map: [String: Emoji] = [:]
        map.reserveCapacity(emoji.count * 2)

        let byCharacter = Dictionary(emoji.map { ($0.character, $0) }, uniquingKeysWith: { first, _ in first })
        for (alias, character) in curated {
            if let item = byCharacter[character] { map[alias] = item }
        }

        for item in emoji where !item.nameDE.isEmpty {
            if map[item.nameDE] == nil { map[item.nameDE] = item }
        }
        for item in emoji where !item.nameEN.isEmpty {
            if map[item.nameEN] == nil { map[item.nameEN] = item }
        }
        for item in emoji {
            for keyword in item.keywords
            where !keyword.contains("_") && keyword.count >= minKeywordAliasLength {
                if map[keyword] == nil { map[keyword] = item }
            }
        }
        return map
    }

    // MARK: - Lookup

    /// Exact `:name:` match. Returns nil for unknown names so the typed text
    /// is left untouched — a wrong guess would silently corrupt what the user
    /// wrote, which is worse than doing nothing.
    func emoji(forAlias alias: String) -> Emoji? {
        aliases[EmojiSearch.normalize(alias)]
    }

    /// Ranked search for the picker. Empty query returns the natural CLDR
    /// order (faces first), which is what an empty search field should show.
    func search(_ query: String, limit: Int = 60) -> [Emoji] {
        let normalized = EmojiSearch.normalize(query)
        guard !normalized.isEmpty else { return Array(all.prefix(limit)) }
        return EmojiSearch.rank(all, query: normalized, limit: limit)
    }
}

/// Pure search logic — no AppKit, no actor isolation, fully unit-testable
/// without a bundle or a running app.
enum EmojiSearch {
    /// Must stay in lockstep with `slugify()` in
    /// `scripts/generate-emoji-data.py`: the generator writes slugs with this
    /// transliteration, so a query normalized differently would simply never
    /// match. Changing one without the other silently breaks umlaut search.
    private static let transliteration: [Character: String] = [
        "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
        "à": "a", "á": "a", "â": "a", "ã": "a", "å": "a",
        "è": "e", "é": "e", "ê": "e", "ë": "e",
        "ì": "i", "í": "i", "î": "i", "ï": "i",
        "ò": "o", "ó": "o", "ô": "o", "õ": "o",
        "ù": "u", "ú": "u", "û": "u",
        "ç": "c", "ñ": "n",
    ]

    static func normalize(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for char in text.lowercased() {
            if let mapped = transliteration[char] {
                out += mapped
            } else if char.isLetter || char.isNumber, char.isASCII {
                out.append(char)
            } else if char == "_" || char == " " || char == "-" {
                out.append("_")
            }
            // Everything else (punctuation, emoji itself) is dropped.
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Lower score = better match. Ties fall back to the source order, so
    /// results are stable across runs instead of shuffling per keystroke.
    private static func score(_ emoji: Emoji, query: String) -> Int? {
        if emoji.nameDE == query || emoji.nameEN == query { return 0 }
        if emoji.nameDE.hasPrefix(query) || emoji.nameEN.hasPrefix(query) { return 1 }
        for keyword in emoji.keywords where keyword == query { return 2 }
        for keyword in emoji.keywords where keyword.hasPrefix(query) { return 3 }
        if emoji.nameDE.contains(query) || emoji.nameEN.contains(query) { return 4 }
        for keyword in emoji.keywords where keyword.contains(query) { return 5 }
        return nil
    }

    static func rank(_ emoji: [Emoji], query: String, limit: Int) -> [Emoji] {
        var scored: [(index: Int, score: Int, emoji: Emoji)] = []
        for (index, item) in emoji.enumerated() {
            if let score = score(item, query: query) {
                scored.append((index, score, item))
            }
        }
        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
        }
        return scored.prefix(limit).map(\.emoji)
    }
}
