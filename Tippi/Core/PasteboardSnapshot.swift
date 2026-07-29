import AppKit

/// Captures the current state of `NSPasteboard.general` and can restore it later.
/// Used to make `⌘C` / `⌘V` round-trips invisible to the user.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

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
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        // Build the restorable items BEFORE clearing. If the snapshot captured
        // only non-materializable (promise/data-provider backed) content, nsItems
        // is empty — clearing first would then wipe the user's real clipboard
        // instead of leaving it untouched.
        let nsItems = items.compactMap { entries -> NSPasteboardItem? in
            guard !entries.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        guard !nsItems.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(nsItems)
    }
}
