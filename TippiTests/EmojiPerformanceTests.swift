import XCTest
@testable import Tippi

/// Performance guards for the two hot paths.
///
/// The inline matcher is the one that matters most: it runs inside the
/// system-wide keystroke monitor, on the main actor, for *every* key the user
/// presses anywhere on the Mac. Anything slow there is felt as typing lag in
/// other apps, which is the worst possible failure mode for this feature.
///
/// The database is loaded from the repo working copy rather than a bundle, so
/// these exercise the real shipped data (1900+ emoji) instead of a fixture.
final class EmojiPerformanceTests: XCTestCase {

    private static var emoji: [Emoji] = {
        // TippiTests/ -> repo root -> Tippi/Resources/emoji-data.json
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tippi/Resources/emoji-data.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        struct File: Decodable { let emoji: [Emoji] }
        return (try? JSONDecoder().decode(File.self, from: data))?.emoji ?? []
    }()

    func testDataSetLoadedForPerformanceRuns() {
        XCTAssertGreaterThan(Self.emoji.count, 1800,
                             "shipped emoji data missing or truncated — perf numbers would be meaningless")
    }

    /// Every keystroke, system-wide. Budget: microseconds, not milliseconds.
    func testInlineMatcherPerKeystrokeCost() {
        // Realistic worst case: a long buffer that is NOT a match, so the
        // matcher runs its full scan before rejecting.
        let buffer = String(repeating: "lorem ipsum dolor ", count: 3) + ":nichttreffer"
        measure {
            for _ in 0..<10_000 {
                _ = EmojiInlineMatcher.candidate(in: buffer)
            }
        }
    }

    /// Also every keystroke, system-wide: ~30 `hasSuffix` checks against the
    /// emoticon table. Runs right after the inline matcher, so their costs add.
    func testEmoticonMatcherPerKeystrokeCost() {
        // Worst case: no emoticon matches, so all candidates are tested.
        let buffer = String(repeating: "lorem ipsum dolor ", count: 3) + "kein treffer"
        measure {
            for _ in 0..<10_000 {
                _ = EmoticonMatcher.match(in: buffer)
            }
        }
    }

    /// Runs on each keystroke *inside the picker's search field* only — a
    /// larger budget than the global path, but still has to feel instant.
    func testSearchAcrossFullDataSet() {
        let queries = ["r", "ra", "rak", "rake", "raket", "rakete"]
        measure {
            for query in queries {
                _ = EmojiSearch.rank(Self.emoji, query: EmojiSearch.normalize(query), limit: 60)
            }
        }
    }

    /// Worst case for search: a single common letter matches a large share of
    /// the set, so ranking has to score and sort almost everything.
    func testSearchWorstCaseSingleCommonLetter() {
        measure {
            _ = EmojiSearch.rank(Self.emoji, query: "e", limit: 60)
        }
    }

    func testNormalizeCost() {
        measure {
            for _ in 0..<10_000 {
                _ = EmojiSearch.normalize("Gesicht mit Freudentränen")
            }
        }
    }
}
