import Carbon
import Foundation

/// The text of the last dictation, kept so ⌃⌥⌘V can write it again, for when it landed in the
/// wrong place or the text box was missed (Michael 2026-11-23, idea from EnviousWispr's
/// "Paste Last Dictation"; docs/SECURE-DESIGN-letztes-diktat.md).
///
/// Memory only, never written to disk or to the log, gone after 30 minutes and when Tippi quits.
/// One entry: a new dictation replaces the old one.
@MainActor
final class LastDictation {
    static let shared = LastDictation()

    nonisolated static let lifetime: TimeInterval = 30 * 60
    nonisolated static let maxCharacters = 100_000

    /// Tests set their own clock.
    var now: () -> Date = { Date() }

    private var text: String?
    private var savedAt: Date?

    init() {}

    /// Keeps `text` as the last dictation. Empty text or a text that is too long clears the
    /// entry instead: an older dictation must not come back after a newer one.
    func remember(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maxCharacters else {
            clear()
            return
        }
        self.text = text
        savedAt = now()
    }

    /// Called by the dictation after it wrote its text. Notes dictation (`.inbox`) and the reply
    /// by voice (`.reply`) keep nothing: the first lands in a note, the second is no dictation
    /// text. Never into or from a password field.
    func rememberDictation(_ text: String, source: DictationSource,
                           isSecure: Bool = IsSecureEventInputEnabled()) {
        guard LastDictationSettings.isEnabled, !isSecure, source != .inbox, source != .reply else { return }
        remember(text)
    }

    /// The text, or `nil` when there is none or it is older than 30 minutes.
    func recall() -> String? {
        guard let text, let savedAt else { return nil }
        guard now().timeIntervalSince(savedAt) <= Self.lifetime else {
            clear()
            return nil
        }
        return text
    }

    func clear() {
        text = nil
        savedAt = nil
    }
}

/// Switch and key combo of "Insert last dictation again". On by default, ⌃⌥⌘V.
@MainActor
enum LastDictationSettings {
    /// See `DictationSettings.store`: `.standard` in the app, a throwaway suite in tests.
    static var store: UserDefaults = .standard
    private static let enabledKey = "dictation.lastDictation.enabled.v1"
    private static let comboKey = "dictation.lastDictationCombo.v1"

    static var isEnabled: Bool {
        get { store.object(forKey: enabledKey) as? Bool ?? true }
        set {
            store.set(newValue, forKey: enabledKey)
            if !newValue { LastDictation.shared.clear() }   // off means the text is gone too
        }
    }

    static var combo: KeyCombo {
        get {
            guard let data = store.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return .lastDictationDefault }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { store.set(data, forKey: comboKey) }
        }
    }
}
