import AppKit
import os

private let overlayLog = Logger(subsystem: "com.tippi.app", category: "screen-ocr")

/// Lässt den Nutzer ein Rechteck auf dem Bildschirm aufziehen.
///
/// Über jedem Bildschirm liegt ein eigenes randloses Fenster. Das Ergebnis sind
/// globale Koordinaten, die `ScreenTextCapture` direkt verwenden kann.
///
/// **Warum die Abbruchwege so ausführlich sind:** Hier liegt ein unsichtbares
/// Fenster über dem gesamten Bildschirm. Bleibt es hängen, wirkt der Rechner
/// eingefroren — für eine App im Autostart der schlimmste Fehlerfall. Deshalb
/// drei unabhängige Auswege: ESC, Rechtsklick und eine harte Zeitgrenze.
@MainActor
final class ScreenSelectionOverlay {

    /// Ohne Auswahl schließt sich das Overlay von selbst. Ein vergessenes
    /// Auswahlfenster darf den Rechner nicht dauerhaft blockieren.
    private static let timeout: TimeInterval = 60

    private var windows: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?

    /// Zeigt das Overlay. `completion` bekommt das Rechteck in globalen
    /// Koordinaten — oder `nil`, wenn abgebrochen wurde.
    func begin(completion: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication

        for screen in NSScreen.screens {
            let view = SelectionView(frame: .zero)
            view.onFinish = { [weak self] rect in self?.finish(rect) }
            view.onCancel = { [weak self] in self?.finish(nil) }

            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false)
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            // Über allem, auch über Vollbild-Apps.
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Nur das Fenster unter dem Mauszeiger nimmt Tasten entgegen; die
        // anderen zeigen bloß die Abdunklung.
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            overlayLog.info("Auswahl nach Zeitablauf geschlossen")
            self?.finish(nil)
        }
    }

    private func finish(_ rect: CGRect?) {
        // defer statt Erfolgspfad: Das Aufräumen muss auch dann laufen, wenn
        // unten etwas schiefgeht.
        defer { teardown() }
        let callback = completion
        completion = nil
        callback?(rect)
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        // Fokus zurück, sonst bleibt Tippi vorne und verdeckt die Arbeit.
        previousApp?.activate()
        previousApp = nil
    }
}

// MARK: - Die zeichnende Ansicht

private final class SelectionView: NSView {

    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Leichte Abdunklung, damit erkennbar ist, dass eine Auswahl läuft.
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        guard let rect = selectionRect else { return }

        // Ausgewählter Bereich wird wieder freigestellt.
        NSColor.clear.set()
        rect.fill(using: .copy)

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()

        // Maße einblenden — hilft beim genauen Treffen kleiner Textstellen.
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let badge = NSRect(x: rect.minX, y: rect.maxY + 4,
                           width: size.width + 10, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: badge.minX + 5, y: badge.minY + 3), withAttributes: attrs)
    }

    private var selectionRect: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil; current = nil; needsDisplay = true }
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
            onCancel?()
            return
        }
        // In globale Bildschirmkoordinaten umrechnen.
        guard let window else { onCancel?(); return }
        let inWindow = convert(rect, to: nil)
        let global = window.convertToScreen(inWindow)
        onFinish?(global)
    }

    /// Zweiter Ausweg neben ESC — ein Rechtsklick bricht ebenfalls ab.
    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {          // ESC
            onCancel?()
        } else {
            // Alles andere wird bewusst NICHT abgefangen. Das Overlay ist zum
            // Auswählen da, nicht zum Mitlesen von Tastatureingaben.
            super.keyDown(with: event)
        }
    }
}
