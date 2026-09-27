import AppKit

/// Captures the current state of `NSPasteboard.general` and can restore it later.
/// Used to make `⌘C` / `⌘V` round-trips invisible to the user.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    /// `changeCount` at capture. Unchanged at restore = nobody wrote → leave
    /// the clipboard alone. `restore()` is also called on paths where Tippi's
    /// ⌘C copied nothing; clearing there wiped the user's real clipboard
    /// (review 2026-09-27).
    private let changeCount: Int

    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type] = data
                }
            }
            return map
        }
        return PasteboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        guard pasteboard.changeCount != changeCount else { return }
        let nsItems = items.compactMap { entries -> NSPasteboardItem? in
            guard !entries.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        // The clipboard WAS changed (by Tippi), so the original state is what
        // counts — including "empty": returning early left Tippi's own text on
        // a clipboard that was empty before (audit 2026-09-27).
        pasteboard.clearContents()
        guard !nsItems.isEmpty else { return }
        pasteboard.writeObjects(nsItems)
    }
}
