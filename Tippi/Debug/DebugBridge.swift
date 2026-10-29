#if DEBUG
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import OSLog
import ScreenCaptureKit
import Security
import SwiftUI

/// Befehlskanal der Bild-Testkopie (docs/SECURE-DESIGN-befehlskanal.md), nur Debug-Build und nur mit Kennung
/// `dev.mwlr.tippi.bild`. Befehle kommen über `debug.sock` (`DebugSocketServer`: Audit-Token gegen
/// `DebugCommand.ctlRequirement` vor dem ersten Byte). Antworten liegen als `Antworten/<id>.json`, Bilder als
/// `Bilder/<id>-<fenster>.png` im eigenen Ordner `~/Library/Application Support/Tippi Bild` (0700).
///
/// Für ein Bild öffnet die Kopie ein eigenes Einstellungsfenster, in dem genau EIN Reiter geladen ist (B5) –
/// das normale Fenster lädt alle Reiter gleichzeitig, auch Anbieter, Snippets und Verlauf.
@MainActor
final class DebugBridge {
    private static let log = Logger(subsystem: "com.tippi.app", category: "debug")
    private static var current: DebugBridge?

    private let directory: URL
    private var server: DebugSocketServer?
    private var windows: [String: NSWindow] = [:]

    private init(directory: URL) {
        self.directory = directory
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tippi Bild", isDirectory: true)
    }

    /// Erlaubte Fenster → einziger geladener Reiter.
    private static func tab(for window: String) -> SettingsTab? {
        switch window {
        case DebugCommand.settingsWindow: return .general
        case DebugCommand.helpWindow: return .help
        case DebugCommand.aboutWindow: return .about
        default: return nil
        }
    }

    static func start() {
        let dir = directory
        guard BildKopie.isActive, current == nil, DebugSocketServer.prepareDirectory(dir) else {
            log.error("Befehlskanal aus: Ordner")
            return
        }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(DebugCommand.ctlRequirement as CFString, [], &req) == errSecSuccess,
              let req else {
            log.error("Befehlskanal aus: Anforderung ungültig")
            return
        }
        let bridge = DebugBridge(directory: dir)
        let server = DebugSocketServer(socketPath: dir.appendingPathComponent("debug.sock").path, requirement: req) { command in
            Task { @MainActor in await bridge.handle(command) }
        }
        do {
            try server.start()
            bridge.server = server
            current = bridge
            log.notice("Befehlskanal bereit")
        } catch {
            log.error("Befehlskanal aus: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ command: DebugCommand) async {
        var answer: [String: Any] = ["v": 1, "id": command.id]
        switch command.kind {
        case .status:
            answer["status"] = status()
        case .appearance(let mode):
            AppearanceSettings.mode = AppearanceSettings.Mode(rawValue: mode) ?? .system
            // Der Reiter Allgemein liest die Darstellung beim Aufbau – neu aufbauen, damit das Bild passt.
            windows.values.forEach { $0.close() }
            windows.removeAll()
            answer["ok"] = true
        case .snapshot(let window):
            answer.merge(await snapshot(window: window, id: command.id)) { $1 }
        }
        write(answer, id: command.id)
    }

    /// Nur Zahlen und Kennungen – keine Titel, keine Inhalte.
    private func status() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let open = NSApp.windows.filter(\.isVisible).compactMap { win -> [String: Any]? in
            guard let id = win.identifier?.rawValue, DebugCommand.snapshotWindows.contains(id) else { return nil }
            return ["id": id, "breite": Int(win.frame.width), "hoehe": Int(win.frame.height)]
        }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return ["version": info["CFBundleShortVersionString"] as? String ?? "?",
                "kennung": Bundle.main.bundleIdentifier ?? "?",
                "bildschirmaufnahme": CGPreflightScreenCaptureAccess(),
                "bedienungshilfen": AXIsProcessTrusted(),
                "eingabeueberwachung": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
                "mikrofon": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
                "modus": AppearanceSettings.mode.rawValue,
                "darstellung": isDark ? "dark" : "light",
                "fenster": open]
    }

    /// Eigenes Einstellungsfenster mit genau einem geladenen Reiter, gleiche Größe und Umgebung wie das echte.
    private func window(_ id: String, tab: SettingsTab) -> NSWindow {
        if let win = windows[id] { return win }
        var view = AnyView(SettingsView(mountedTabs: [tab], initialTab: tab))
        if let app = AppDelegate.shared {
            view = AnyView(SettingsView(mountedTabs: [tab], initialTab: tab)
                .environmentObject(app.permissions)
                .environmentObject(app.hotkeyManager)
                .environmentObject(app.keyMonitor)
                .environmentObject(app.snippetStore))
        }
        let controller = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: controller)
        win.styleMask = [.titled, .closable, .resizable]
        win.title = String(localized: "settings.window.title")
        win.identifier = NSUserInterfaceItemIdentifier(id)
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 860, height: 640))
        win.center()
        windows[id] = win
        return win
    }

    /// Öffnet das eigene Fenster, wartet kurz und nimmt NUR dieses Fenster per ScreenCaptureKit auf. Das Fenster
    /// öffnet auch ohne Freigabe – `status` zeigt dann, dass es sich ohne Absturz aufbaut.
    private func snapshot(window id: String, id answerID: String) async -> [String: Any] {
        guard let tab = Self.tab(for: id) else { return ["ok": false, "fehler": "Fenster nicht erlaubt"] }
        let win = window(id, tab: tab)
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(900))
        guard CGPreflightScreenCaptureAccess() else {
            // Trägt „Tippi Bild“ in die Liste der Systemeinstellungen ein (einmalig mit Systemdialog).
            CGRequestScreenCaptureAccess()
            return ["ok": false, "fenster_offen": win.isVisible,
                    "fehler": "Bildschirmaufnahme nicht freigegeben – in den Systemeinstellungen erlauben, App neu starten"]
        }
        let windowID = CGWindowID(win.windowNumber)
        let scale = win.backingScaleFactor
        let size = win.frame.size
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return ["ok": false, "fehler": "Fenster nicht in ScreenCaptureKit"]
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: config)
            let folder = directory.appendingPathComponent("Bilder", isDirectory: true)
            guard DebugSocketServer.prepareDirectory(folder),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                return ["ok": false, "fehler": "Bild nicht gespeichert"]
            }
            let file = folder.appendingPathComponent("\(answerID)-\(id).png")
            try png.write(to: file, options: .atomic)
            return ["ok": true, "datei": file.path, "breite": image.width, "hoehe": image.height]
        } catch {
            return ["ok": false, "fehler": "Aufnahme: \(error.localizedDescription)"]
        }
    }

    private func write(_ answer: [String: Any], id: String) {
        let folder = directory.appendingPathComponent("Antworten", isDirectory: true)
        guard DebugSocketServer.prepareDirectory(folder),
              let data = try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]) else {
            Self.log.error("Antwort nicht geschrieben")
            return
        }
        do {
            try data.write(to: folder.appendingPathComponent("\(id).json"), options: .atomic)
        } catch {
            Self.log.error("Antwort nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
        Self.log.notice("Befehl ausgeführt")
    }
}
#endif
