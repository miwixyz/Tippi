import AppKit
import ApplicationServices
import os

/// Chromium- und Electron-Apps (Helium, Chrome, Claude, Obsidian …) bauen ihren
/// Bedienungshilfen-Baum erst, wenn jemand ihn anfordert — sonst liefern sie
/// `role=?` und keine Textfelder (Messung 2026-11-04, Helium). `AXManualAccessibility`
/// schaltet ihn ein, ohne dass der Nutzer `chrome://accessibility` anfassen muss.
/// Nur dieses Attribut, nicht `AXEnhancedUserInterface`: Letzteres bremst native
/// Apps (Fensteranimationen); es kommt nur als Rückfall für erkannte Chromium-Apps
/// zum Einsatz. Native Apps kennen `AXManualAccessibility` nicht — dort scheitert
/// der Aufruf folgenlos.
enum ChromiumAccessibility {
    private static let log = Logger(subsystem: "com.tippi.app", category: "capture")

    /// Pro Prozess einmal: das Attribut bleibt gesetzt, solange die App läuft.
    @MainActor private static var woken = Set<pid_t>()
    /// Letzter gescheiterter Versuch je Prozess (App hängt): erst nach
    /// `retryAfter` erneut, nicht bei jedem Klick und jeder Tipp-Pause.
    @MainActor private static var failedAt: [pid_t: Date] = [:]
    static let retryAfter: TimeInterval = 5
    /// Läuft auf dem Hauptthread vor jeder Abfrage. Ohne eigene Grenze galt
    /// Tippis globale von 2 s (Audit 2026-11-17, Fund 5).
    static let timeout: Float = 0.5

    /// Setzt `AXManualAccessibility` auf dem App-Element von `pid`, einmal je
    /// Prozess. Ein fehlgeschlagener Versuch (App hängt, Attribut unbekannt)
    /// wird frühestens nach `retryAfter` wiederholt, solange der Fehler kein
    /// „Attribut nicht unterstützt" ist.
    ///
    /// Eigenes App-Element statt `appElement`: Ein Zeitlimit hängt am Element,
    /// und das des Aufrufers soll seines behalten.
    @MainActor
    static func wake(_ appElement: AXUIElement, pid: pid_t, now: Date = Date()) {
        guard pid != ProcessInfo.processInfo.processIdentifier, !woken.contains(pid),
              !isWaitingAfterFailure(pid: pid, now: now) else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        let result = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        switch result {
        case .success:
            woken.insert(pid)
            failedAt[pid] = nil
            log.notice("ax wake: AXManualAccessibility set pid=\(pid)")
        case .attributeUnsupported, .actionUnsupported, .noValue:
            // Electron kennt AXManualAccessibility, Chromium-Browser (Helium, Chrome,
            // Edge) nur AXEnhancedUserInterface (Messung 2026-11-05: -25205). Dieses
            // Attribut bremst native Apps — nur für erkannte Chromium-Apps setzen.
            woken.insert(pid)
            guard isChromiumBased(pid: pid) else {
                log.notice("ax wake: native pid=\(pid) code=\(result.rawValue)")
                return
            }
            let enhanced = AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            log.notice("ax wake: AXEnhancedUserInterface pid=\(pid) code=\(enhanced.rawValue)")
        default:
            // App antwortet nicht o. Ä. — nach `retryAfter` wieder versuchen
            failedAt[pid] = now
            log.notice("ax wake: failed pid=\(pid) code=\(result.rawValue)")
        }
    }

    @MainActor
    static func isWaitingAfterFailure(pid: pid_t, now: Date = Date()) -> Bool {
        guard let failed = failedAt[pid] else { return false }
        return now.timeIntervalSince(failed) < retryAfter
    }

    /// Chromium-Forks tragen ihre Helfer im Bundle: `… Helper (Renderer).app` direkt in
    /// `Frameworks` (Electron) oder in `<Name> Framework.framework/Versions/*/Helpers`.
    static func isChromiumBased(pid: pid_t) -> Bool {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: frameworks.path) else { return false }
        if entries.contains(where: { $0.contains("Helper (Renderer)") }) { return true }
        for entry in entries where entry.hasSuffix("Framework.framework") {
            let versions = frameworks.appendingPathComponent(entry).appendingPathComponent("Versions")
            for version in (try? fm.contentsOfDirectory(atPath: versions.path)) ?? [] {
                let helpers = versions.appendingPathComponent(version).appendingPathComponent("Helpers")
                if let names = try? fm.contentsOfDirectory(atPath: helpers.path),
                   names.contains(where: { $0.contains("Helper (Renderer)") }) { return true }
            }
        }
        return false
    }
}
