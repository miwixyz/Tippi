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
}
