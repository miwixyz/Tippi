import AppKit
import XCTest
@testable import Tippi

/// Highlight, bullet list, quotes and the two new bracket pairs (2026-09-28).
final class LocalTextEncloseAndListTests: XCTestCase {

    // MARK: - Enclosing pairs

    func testBracketPairsWrapTheSelection() {
        XCTAssertEqual(LocalTextTransformer.brackets("Kino"), "(Kino)")
        XCTAssertEqual(LocalTextTransformer.squareBrackets("Kino"), "[Kino]")
        XCTAssertEqual(LocalTextTransformer.curlyBraces("Kino"), "{Kino}")
    }

    func testQuotesUseTheSystemDelimiters() {
        let (open, close) = LocalTextTransformer.quoteDelimiters
        XCTAssertFalse(open.isEmpty)
        XCTAssertFalse(close.isEmpty)
        XCTAssertEqual(LocalTextTransformer.quotes("Kino"), open + "Kino" + close)
    }

    /// The button shows exactly the pair the action inserts.
    func testQuotesButtonShowsTheInsertedPair() {
        let action = LocalTextAction.all.first { $0.kind == .quotes }
        let (open, close) = LocalTextTransformer.quoteDelimiters
        XCTAssertEqual(action?.label, open + " " + close)
    }

    // MARK: - Bullet list

    func testBulletListPrefixesEveryLine() {
        XCTAssertEqual(LocalTextTransformer.bulletList("Äpfel\nBirnen"), "- Äpfel\n- Birnen")
    }

    func testBulletListSingleLine() {
        XCTAssertEqual(LocalTextTransformer.bulletList("Kino"), "- Kino")
    }

    func testBulletListKeepsEmptyLinesAndIndentation() {
        XCTAssertEqual(
            LocalTextTransformer.bulletList("Obst\n\n  Äpfel\n\tBirnen\n   "),
            "- Obst\n\n  - Äpfel\n\t- Birnen\n   ")
    }

    /// A second click must not produce `- - `; an already bulleted selection is
    /// an identity case the writer then refuses to write.
    func testBulletListIsIdempotent() {
        let once = LocalTextTransformer.bulletList("a\nb")
        XCTAssertEqual(LocalTextTransformer.bulletList(once), once)
    }

    func testBulletListOnlyAddsMissingBullets() {
        XCTAssertEqual(LocalTextTransformer.bulletList("- a\nb"), "- a\n- b")
    }

    /// `components(separatedBy: .newlines)` splits `\r\n` twice and would
    /// insert an empty line between every item.
    func testBulletListDoesNotDoubleCRLFLineBreaks() {
        XCTAssertEqual(LocalTextTransformer.bulletList("a\r\nb"), "- a\n- b")
    }

    // MARK: - Highlight

    func testHighlightIsYellowBackgroundWithUnchangedPlainText() {
        let action = LocalTextAction.all.first { $0.kind == .highlight }
        guard case .richReplacement(let attributed, let fallback)? = action?.perform(on: "Kino") else {
            return XCTFail("highlight must be a rich replacement")
        }
        XCTAssertEqual(fallback, "Kino", "no Markdown fallback — decided 2026-09-28")
        XCTAssertEqual(attributed.string, "Kino")
        let colour = attributed.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(colour, NSColor.yellow)
        let text = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(text, NSColor.black, "explicit dark text, not the app's dynamic colour")
    }

    // MARK: - Selection bar layout

    /// Every action appears in exactly one of the two rows — a new category
    /// that neither row filters for would silently vanish from the bar.
    func testSelectionBarRowsCoverEveryActionOnce() {
        let ids = (SelectionActionBarView.topRow + SelectionActionBarView.bottomRow).map(\.id)
        XCTAssertEqual(ids.sorted(), LocalTextAction.all.map(\.id).sorted())
    }

    /// The point of the second row: the bar must stay well inside a 13-inch
    /// screen (1280 pt) instead of the ~890 pt a single row would need.
    func testSelectionBarStaysCompact() {
        XCTAssertLessThan(SelectionActionBarView.width, 560)
    }
}
