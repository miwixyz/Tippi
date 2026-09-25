import Foundation

/// Einstellungen für „Text aus Bildschirmausschnitt" — gleiche Bauform wie
/// `NotesSettings`/`TranslateSettings` (Schalter + belegbarer Hotkey), angebunden
/// über `AppDelegate.restartScreenOCRHotkey()`.
@MainActor
enum ScreenOCRSettings {
    /// See `DictationSettings.store`: `.standard` in the app, a throwaway suite in
    /// tests — the test host shares the installed app's preferences file.
    static var store: UserDefaults = .standard
    private static let enabledKey = "screenOCR.hotkey.enabled"
    private static let comboKey = "screenOCR.hotkeyCombo.v1"
    private static let concealKey = "screenOCR.concealFromClipboardHistory"
    private static let joinKey = "screenOCR.joinLines"

    /// **Ab Werk AUS** — anders als Übersetzen, Emoji und Notizen.
    ///
    /// Der Grund ist nicht Vorsicht um ihrer selbst willen: Diese Funktion
    /// verlangt die Berechtigung „Bildschirmaufnahme", und die ist eine
    /// Dauervollmacht — einmal erteilt, kann Tippi jederzeit den gesamten
    /// Bildschirm lesen. Zusammen mit dem vorhandenen Bedienungshilfen-Zugriff
    /// ergäbe das „sieht alles und schreibt überall". Wer die Funktion nicht
    /// braucht, soll die Vollmacht nie erteilen müssen.
    static var isEnabled: Bool {
        get { store.object(forKey: enabledKey) as? Bool ?? false }
        set { store.set(newValue, forKey: enabledKey) }
    }

    /// ⌥⌘2 — die Ziffern sind bei Tippi noch frei, und die Taste liegt nah an
    /// der System-Bildschirmfoto-Belegung (⇧⌘4), ohne mit ihr zu kollidieren.
    static var combo: KeyCombo {
        get {
            guard let data = store.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return KeyCombo(keyCode: 19, modifiers: [.option, .command])
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: comboKey)
            }
        }
    }

    /// Zeilenumbrüche innerhalb von Absätzen zusammenführen.
    ///
    /// Die Texterkennung liefert jede Bildschirmzeile einzeln — eine Eigenschaft
    /// des Layouts, nicht des Textes. Beim Einfügen steht dann mitten im Satz
    /// ein Umbruch. Absätze, Aufzählungen und Satzenden bleiben erhalten;
    /// siehe `RecognizedTextJoiner`.
    ///
    /// **Ab Werk AN**: Fließtext ist der häufigere Fall. Wer Code oder Tabellen
    /// erfasst, schaltet es aus — dort trägt jede Zeile Bedeutung.
    static var joinLines: Bool {
        get { store.object(forKey: joinKey) as? Bool ?? true }
        set { store.set(newValue, forKey: joinKey) }
    }

    /// Erkannten Text vor Zwischenablage-Verläufen verbergen
    /// (`org.nspasteboard.ConcealedType`).
    ///
    /// **Ab Werk AUS.** Raycast, Alfred und Paste lesen jede Änderung mit und
    /// behalten sie dauerhaft — was Tippi nach Sekunden vergisst, liegt dort
    /// monatelang. Eine Dauer-Verbergung hätte den Text aber auch aus der
    /// eigenen Verlaufssuche entfernt, wo er meist gesucht wird. Deshalb ein
    /// Schalter für den Moment, in dem etwas Heikles erfasst wird, statt einer
    /// Voreinstellung, die im Alltag stört (entschieden 2026-09-21).
    static var concealFromClipboardHistory: Bool {
        get { store.object(forKey: concealKey) as? Bool ?? false }
        set { store.set(newValue, forKey: concealKey) }
    }
}
