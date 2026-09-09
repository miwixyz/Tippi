import Foundation

/// Shared state between the picker panel (which owns keyboard handling) and
/// the SwiftUI view (which renders). Kept as a separate object because the
/// arrow-key navigation lives in an `NSEvent` monitor on the panel — a plain
/// `@State` in the view would not be reachable from there.
@MainActor
final class EmojiPickerModel: ObservableObject {
    /// Grid width. Also the arrow-key row stride, so the two can never drift.
    static let columns = 8

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            refresh()
        }
    }

    @Published private(set) var results: [Emoji] = []
    @Published var selectedIndex: Int = 0

    /// True while the search field is empty and we are showing recents rather
    /// than search results — the view labels the section differently.
    @Published private(set) var isShowingRecents: Bool = false

    private let database: EmojiDatabase

    init(database: EmojiDatabase = .shared) {
        self.database = database
        refresh()
    }

    var selected: Emoji? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func refresh() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let recents = EmojiSettings.recents
            if !recents.isEmpty {
                // Map stored characters back to full entries; anything no
                // longer in the database (data regenerated, emoji removed)
                // is dropped rather than rendered as a blank cell.
                let byCharacter = Dictionary(
                    database.all.map { ($0.character, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let mapped = recents.compactMap { byCharacter[$0] }
                if !mapped.isEmpty {
                    results = mapped
                    isShowingRecents = true
                    selectedIndex = 0
                    return
                }
            }
            results = database.search("")
            isShowingRecents = false
            selectedIndex = 0
            return
        }

        results = database.search(trimmed)
        isShowingRecents = false
        selectedIndex = 0
    }

    // MARK: - Keyboard navigation

    func moveSelection(columnDelta: Int = 0, rowDelta: Int = 0) {
        guard !results.isEmpty else { return }
        let target = selectedIndex + columnDelta + rowDelta * Self.columns
        // Clamp instead of wrapping: wrapping from the last item back to the
        // first makes it easy to lose track of where the cursor is in a grid
        // this dense.
        selectedIndex = min(max(target, 0), results.count - 1)
    }
}
