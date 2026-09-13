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
