import Foundation
import os

private let idleLog = Logger(subsystem: "com.tippi.app", category: "mlx-idle")

/// Nimmt die lokalen Modelle nach 15 Minuten ohne Nutzung aus dem Speicher:
/// das Rechenwerk der Autovervollständigung (MLX Swift im Prozess) und den von
/// Tippi gestarteten `mlx_lm.server`. Gemessen 2026-11-17: beide hielten
/// Gemma 4 E4B (4,27 GB + 4,4 GB) bis zum Beenden der App. Einstellung
/// `mlx.unloadWhenIdle.v1`, ab Werk AN.
///
/// Nutzung meldet jeder Weg, der ein lokales Modell anfasst (`noteUse`, bzw.
/// `beginRequest`/`endRequest` um eine laufende Server-Anfrage). Beim nächsten
/// Gebrauch startet alles über die bestehenden Wege neu: Server über
/// `MLXServerManager.start()`, Rechenwerk über `AutocompleteEngineHost`.
///
/// Kein Takt: Es gibt höchstens einen schlafenden Task. Nutzung verschiebt nur
/// den Zeitstempel; wacht der Task zu früh auf, schläft er die Restzeit.
@MainActor
final class LocalModelIdleUnloader {
    static let shared = LocalModelIdleUnloader()

    /// Wie lange nichts passiert sein muss.
    nonisolated static let idleLimit: TimeInterval = 15 * 60
    /// Ist zum Ablauf gerade etwas in Arbeit (Diktat, Anfrage), wird so lange
    /// später erneut geprüft.
    nonisolated static let busyRecheck: TimeInterval = 60

    /// `.standard` in der App, eine Wegwerf-Suite in Tests.
    static var store: UserDefaults = .standard
    static let enabledKey = "mlx.unloadWhenIdle.v1"

    /// „Lokales Modell nach 15 Min ohne Nutzung entladen". Ab Werk AN.
    static var isEnabled: Bool {
        get { store.object(forKey: enabledKey) as? Bool ?? true }
        set { store.set(newValue, forKey: enabledKey) }
    }

    /// Uhr — in Tests ersetzbar.
    var now: () -> Date = Date.init
    /// Läuft gerade etwas, das ein lokales Modell braucht (Diktat, Vorschlag)?
    var isBusy: () -> Bool = { false }
    /// Entlädt Rechenwerk und eigenen Server. Gesetzt von `AppDelegate`.
    var unload: () -> Void = {}

    private(set) var lastUse: Date?
    private(set) var activeRequests = 0
    private var timer: Task<Void, Never>?

    /// Ein lokales Modell wurde gerade benutzt.
    func noteUse() {
        lastUse = now()
        guard timer == nil, Self.isEnabled else { return }
        schedule(after: Self.idleLimit)
    }

    /// Eine Anfrage an den MLX-Server beginnt — bis `endRequest` wird nicht entladen.
    func beginRequest() {
        activeRequests += 1
        noteUse()
    }

    func endRequest() {
        activeRequests = max(0, activeRequests - 1)
        noteUse()
    }

    /// Einstellung umgeschaltet: aus → kein Timer; an → ab jetzt zählen.
    func settingChanged() {
        timer?.cancel()
        timer = nil
        if Self.isEnabled { noteUse() }
    }

    enum Decision: Equatable {
        /// Nichts tun, kein Timer (aus oder nie benutzt).
        case keep
        /// In so vielen Sekunden erneut prüfen.
        case wait(TimeInterval)
        case unload
    }

    /// Reine Entscheidung, ohne Modell und ohne Uhr testbar.
    nonisolated static func decide(enabled: Bool, lastUse: Date?, now: Date, busy: Bool,
                                   limit: TimeInterval = idleLimit,
                                   busyRecheck: TimeInterval = busyRecheck) -> Decision {
        guard enabled, let lastUse else { return .keep }
        let remaining = lastUse.addingTimeInterval(limit).timeIntervalSince(now)
        if remaining > 0 { return .wait(remaining) }
        return busy ? .wait(busyRecheck) : .unload
    }

    /// Wird vom Timer aufgerufen; in Tests direkt.
    func evaluate() {
        timer = nil
        let decision = Self.decide(enabled: Self.isEnabled, lastUse: lastUse, now: now(),
                                   busy: activeRequests > 0 || isBusy())
        switch decision {
        case .keep:
            break
        case .wait(let seconds):
            schedule(after: seconds)
        case .unload:
            lastUse = nil
            idleLog.notice("unloading local models after idle period")
            unload()
        }
    }

    private func schedule(after seconds: TimeInterval) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
}
