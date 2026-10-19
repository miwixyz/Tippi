import Foundation

/// Tippi vorübergehend pausieren (Michael, 2026-10-19: „Es muss eine einfache Möglichkeit geben
/// Tippi vorübergehend zu pausieren“). Pausiert wird nur, was Tippi **von selbst** tut:
/// Popup beim Markieren, Autovervollständigung, Textbausteine samt Emoji-Ersetzung.
/// Tastenkürzel löst der Nutzer selbst aus — die laufen weiter (Michaels Wahl „a“).
///
/// Gespeichert als Endzeitpunkt, damit eine Pause einen Neustart von Tippi übersteht.
/// „Bis ich fortsetze“ = `Date.distantFuture`.
enum TippiPause {

    static let untilKey = "tippi.pause.until"

    enum Duration: CaseIterable, Equatable {
        case minutes15, hour1, untilTomorrow, untilResumed
    }

    /// Ende der Pause für eine Wahl. „Bis morgen“ = morgen 6:00 Uhr Ortszeit.
    static func end(for duration: Duration, now: Date, calendar: Calendar = .current) -> Date {
        switch duration {
        case .minutes15: return now.addingTimeInterval(15 * 60)
        case .hour1: return now.addingTimeInterval(60 * 60)
        case .untilResumed: return .distantFuture
        case .untilTomorrow:
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(byAdding: .hour, value: 6, to: startOfTomorrow) ?? startOfTomorrow
        }
    }

    static func pausedUntil(_ defaults: UserDefaults = .standard) -> Date? {
        let raw = defaults.double(forKey: untilKey)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    static func isActive(now: Date = Date(), _ defaults: UserDefaults = .standard) -> Bool {
        guard let until = pausedUntil(defaults) else { return false }
        return until > now
    }

    static func pause(until end: Date, _ defaults: UserDefaults = .standard) {
        defaults.set(end.timeIntervalSince1970, forKey: untilKey)
    }

    static func resume(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: untilKey)
    }
}
