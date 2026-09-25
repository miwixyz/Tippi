import AppKit

/// App-wide light/dark choice: follow the system, or force light or dark.
///
/// Applied through `NSApp.appearance`, which every Tippi window inherits —
/// Settings, Notes, previews, popups. The three panels that set their own
/// `appearance` (translate, emoji picker, emoji suggestions) do so because a
/// borderless non-activating panel can snapshot `.aqua` at creation and then
/// not follow the system; they ask `panelAppearance()` here instead of reading
/// the system style themselves, so there is one rule, not four.
///
/// Deliberately **not** in `SyncedPreferences`: the right choice depends on
/// the Mac (a bright office display vs. a laptop used at night), and the
/// allow-list there only carries settings that mean the same on every machine.
@MainActor
enum AppearanceSettings {
    enum Mode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark
        var id: String { rawValue }

        /// `nil` = inherit (follow the system).
        var appearanceName: NSAppearance.Name? {
            switch self {
            case .system: return nil
            case .light: return .aqua
            case .dark: return .darkAqua
            }
        }

        /// Whether Tippi draws dark, given what the system currently does.
        func isDark(systemIsDark: Bool) -> Bool {
            switch self {
            case .system: return systemIsDark
            case .light: return false
            case .dark: return true
            }
        }
    }

    static let modeKey = "appearance.mode.v1"

    /// Stored mode; anything missing or unknown reads as `.system`.
    static func storedMode(in defaults: UserDefaults) -> Mode {
        Mode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .system
    }

    static var mode: Mode {
        get { storedMode(in: .standard) }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            apply()
        }
    }

    /// The system's own light/dark setting, independent of Tippi's override.
    /// Read from the global preference, not `NSApp.effectiveAppearance` — the
    /// latter already reflects the override and would answer the wrong question.
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// The one answer to "is Tippi dark right now?".
    static var isDark: Bool { mode.isDark(systemIsDark: systemIsDark) }

    /// Explicit appearance for panels that must not rely on inheritance.
    static func panelAppearance() -> NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    /// Sets `NSApp.appearance`. Call at launch and whenever the mode changes
    /// (the setter does the latter).
    static func apply() {
        NSApp.appearance = mode.appearanceName.flatMap { NSAppearance(named: $0) }
    }
}
