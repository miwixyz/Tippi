import AppKit

/// Notes window preferences, synced across Macs via
/// `NSUbiquitousKeyValueStore` — a small key-value store built exactly for
/// this kind of thing (1 MB / 1024 keys is plenty for a window frame).
///
/// Deliberately separate from `NotesStore`: note CONTENT goes through the
/// iCloud Documents container (can grow, needs file coordination). This type
/// holds ONLY window chrome. It must never carry API keys, provider
/// credentials, or any other Tippi setting — those stay local/Keychain
/// (Sicherheitsgrenze aus dem Feature-Scope, nicht verhandelbar).
enum NotesPreferences {
    private static let store = NSUbiquitousKeyValueStore.default

    private enum Keys {
        static let frame = "notes.window.frame.v1"
        static let pinned = "notes.window.pinned.v1"
        static let fontName = "notes.editor.fontName.v1"
        static let fontSize = "notes.editor.fontSize.v1"
        static let favoriteIDs = "notes.favoriteIDs.v1"
        static let quickNoteIDs = "notes.quickNoteIDs.v1"
        static let quickNotesSize = "notes.quickNotes.size.v1"
        static let sortOrder = "notes.list.sortOrder.v1"
        static let sortReversed = "notes.list.sortReversed.v1"
    }

    /// Sortierung der Notizliste (Geändert / Erstellt / Name). Unbekannter Wert → Geändert.
    static var sortOrder: NoteSortOrder {
        get { store.string(forKey: Keys.sortOrder).flatMap(NoteSortOrder.init(rawValue:)) ?? .modified }
        set { store.set(newValue.rawValue, forKey: Keys.sortOrder) }
    }

    static var sortReversed: Bool {
        get { store.bool(forKey: Keys.sortReversed) }
        set { store.set(newValue, forKey: Keys.sortReversed) }
    }

    /// `nil` when no frame has been saved yet (first launch on this
    /// iCloud account) — caller falls back to a centered default size.
    static var windowFrame: NSRect? {
        get {
            guard let string = store.string(forKey: Keys.frame) else { return nil }
            return NSRectFromString(string)
        }
        set {
            if let newValue {
                store.set(NSStringFromRect(newValue), forKey: Keys.frame)
            } else {
                store.removeObject(forKey: Keys.frame)
            }
        }
    }

    /// Whether the Notes window floats above every other app's windows and
    /// stays visible when switching apps, Spaces, or into a full-screen app —
    /// the macOS meaning of "pin". Off by default: a window that silently
    /// outranks everything else is a bigger behavioral change than an
    /// explicit opt-in belongs to.
    static var isPinned: Bool {
        get { store.bool(forKey: Keys.pinned) }
        set { store.set(newValue, forKey: Keys.pinned) }
    }

    /// `nil` means "system font" — `PlainTextEditor` falls back to that, not
    /// to a hardcoded family, so a fresh install matches whatever the user's
    /// Mac already looks like everywhere else.
    static var fontName: String? {
        get { store.string(forKey: Keys.fontName) }
        set {
            if let newValue {
                store.set(newValue, forKey: Keys.fontName)
            } else {
                store.removeObject(forKey: Keys.fontName)
            }
        }
    }

    /// 0 means "not set yet" — caller falls back to `NSFont.systemFontSize`.
    static var fontSize: Double {
        get { store.double(forKey: Keys.fontSize) }
        set { store.set(newValue, forKey: Keys.fontSize) }
    }

    /// IDs of starred notes — small metadata (a list of UUIDs), same
    /// justification as everything else in this type. Stored as an array of
    /// UUID strings since `NSUbiquitousKeyValueStore` has no native Set type.
    static var favoriteIDs: Set<UUID> {
        get { parseFavoriteIDs(from: store.array(forKey: Keys.favoriteIDs) as? [String] ?? []) }
        set { store.set(Array(newValue).map(\.uuidString), forKey: Keys.favoriteIDs) }
    }

    static func toggleFavorite(_ id: UUID) {
        var ids = favoriteIDs
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        favoriteIDs = ids
    }

    /// Extracted so the parsing logic (drop anything that isn't a real UUID —
    /// e.g. a stray value synced from some future, incompatible version) is
    /// unit-testable without touching the real `NSUbiquitousKeyValueStore`.
    static func parseFavoriteIDs(from raw: [String]) -> Set<UUID> {
        Set(raw.compactMap(UUID.init(uuidString:)))
    }

    // MARK: - Quick notes (Menüleiste)

    /// How many notes can sit as tabs behind the menu bar icon (Michael, 2026-11-09).
    static let maxQuickNotes = 3

    /// Notes shown as tabs when the menu bar icon is clicked, in tab order.
    /// Same storage idea as `favoriteIDs`, but an ordered array: the order a
    /// note was marked is the order of its tab.
    static var quickNoteIDs: [UUID] {
        get { parseQuickNoteIDs(from: store.array(forKey: Keys.quickNoteIDs) as? [String] ?? []) }
        set { store.set(newValue.map(\.uuidString), forKey: Keys.quickNoteIDs) }
    }

    /// Marks or unmarks a note. Returns `false` when the note could not be
    /// marked because all slots are taken. `existing` = IDs of notes that still
    /// exist, so a deleted note never blocks a slot.
    @discardableResult
    static func toggleQuickNote(_ id: UUID, existing: Set<UUID>) -> Bool {
        guard let next = toggledQuickNotes(quickNoteIDs, toggling: id, existing: existing) else { return false }
        quickNoteIDs = next
        return true
    }

    /// Pure logic behind `toggleQuickNote`, unit-testable without touching the
    /// real `NSUbiquitousKeyValueStore`. `nil` = full, nothing changed.
    static func toggledQuickNotes(_ ids: [UUID], toggling id: UUID, existing: Set<UUID>,
                                  max: Int = maxQuickNotes) -> [UUID]? {
        var live = ids.filter { existing.contains($0) }
        if let index = live.firstIndex(of: id) {
            live.remove(at: index)
            return live
        }
        guard live.count < max else { return nil }
        live.append(id)
        return live
    }

    /// Drops non-UUIDs and duplicates, keeps order, caps at `max`.
    static func parseQuickNoteIDs(from raw: [String], max: Int = maxQuickNotes) -> [UUID] {
        var seen = Set<UUID>()
        let ids = raw.compactMap(UUID.init(uuidString:)).filter { seen.insert($0).inserted }
        return Array(ids.prefix(max))
    }

    /// Popover size, set with its resize grip. Synced like the Notes window frame.
    static var quickNotesSize: CGSize {
        get {
            guard let string = store.string(forKey: Keys.quickNotesSize) else { return defaultQuickNotesSize }
            return clampedQuickNotesSize(NSSizeFromString(string))
        }
        set { store.set(NSStringFromSize(clampedQuickNotesSize(newValue)), forKey: Keys.quickNotesSize) }
    }

    static let defaultQuickNotesSize = CGSize(width: 520, height: 440)

    /// Keeps the popover usable: never smaller than three readable tabs, never
    /// larger than a typical screen half.
    static func clampedQuickNotesSize(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, 360), 1000), height: min(max(size.height, 260), 900))
    }

    /// The marked notes that still exist, in tab order.
    static func quickNotes(ids: [UUID], in notes: [Note]) -> [Note] {
        ids.compactMap { id in notes.first { $0.id == id } }
    }

    /// Resolves the two stored values into an actual font, falling back to
    /// the system font whenever the name is unset or no longer installed
    /// (e.g. synced from a Mac that has a font this one doesn't).
    static var editorFont: NSFont {
        let size = fontSize > 0 ? CGFloat(fontSize) : NSFont.systemFontSize
        if let fontName, let font = NSFont(name: fontName, size: size) {
            return font
        }
        return .systemFont(ofSize: size)
    }
}
