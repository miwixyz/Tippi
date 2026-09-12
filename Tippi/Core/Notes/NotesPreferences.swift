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
}
