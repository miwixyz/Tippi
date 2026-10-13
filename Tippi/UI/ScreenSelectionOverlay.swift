import AppKit
import QuartzCore
import SwiftUI
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
///
/// **Gestaltung ab 2026-10-13** (Michael: „nicht genau erkennbar, wann man
/// loslegen kann“, Design moderner): Das Standbild sieht exakt aus wie der
/// echte Bildschirm — mit nur 22 % Abdunklung und einem Fadenkreuz, das erst
/// bei Mausbewegung kam, war der Moment „jetzt bereit“ unsichtbar. Jetzt:
/// deutliche Abdunklung mit kurzem Einblenden, Fadenkreuz sofort, Glas-Kapsel
/// mit Hinweis. Auswahl im Stil des macOS-Bildschirmfotos (⌘⇧4): weißer
/// Rahmen mit Schatten, Eckwinkel, Maße als Glas-Kapsel.
@MainActor
final class ScreenSelectionOverlay {

    /// Ohne Auswahl schließt sich das Overlay von selbst. Ein vergessenes
    /// Auswahlfenster darf den Rechner nicht dauerhaft blockieren.
    private static let timeout: TimeInterval = 60

    private var windows: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?

    /// Zeigt das Overlay über den **eingefrorenen** Bildschirmen.
    ///
    /// `frozen` ist das Standbild, das vor dem Öffnen dieses Overlays
    /// aufgenommen wurde. Es wird als Hintergrund gezeigt — deshalb ist
    /// sichtbar, was tatsächlich aufgenommen wurde, und ein Pop-Up bleibt im
    /// Bild, obwohl `NSApp.activate` es real geschlossen hat.
    ///
    /// `completion` bekommt das Rechteck in globalen Koordinaten — oder `nil`
    /// bei Abbruch.
    func begin(frozen: [ScreenTextCapture.FrozenScreen],
               completion: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication

        let mouse = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main

        for screen in NSScreen.screens {
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            // Zuordnung über die Geometrie: `frozen` traegt dieselben
            // NSScreen-Frames, aus denen es erzeugt wurde.
            view.configure(
                frozenImage: frozen.first { $0.frame == screen.frame }?.image,
                scale: screen.backingScaleFactor,
                // Hinweis nur auf dem Bildschirm mit dem Mauszeiger, knapp
                // unter Menüleiste bzw. Notch (`visibleFrame`).
                hintTopInset: screen == mouseScreen
                    ? screen.frame.maxY - screen.visibleFrame.maxY + 18
                    : nil
            )
            view.onFinish = { [weak self] rect in self?.finish(rect) }
            view.onCancel = { [weak self] in self?.finish(nil) }

            let window = OverlayWindow(contentRect: screen.frame,
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
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Nur das Fenster unter dem Mauszeiger nimmt Tasten entgegen; die
        // anderen zeigen bloß die Abdunklung.
        // A plain borderless NSWindow can never become key (measured:
        // canBecomeKey == false), so `keyDown` never reached the view and the
        // documented ESC exit did nothing (audit 2026-09-27). OverlayWindow
        // allows it; the view must also be first responder.
        NSApp.activate(ignoringOtherApps: true)
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        keyWindow?.makeKey()
        if let keyWindow { keyWindow.makeFirstResponder(keyWindow.contentView) }

        // Kurzes Einblenden: Der Wechsel vom echten Bildschirm zum Standbild
        // wird als Bewegung sichtbar — das ist das Signal „jetzt bereit“.
        // Mausereignisse kommen schon während der Animation an.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            for window in windows { window.animator().alphaValue = 1 }
        }
        // Fadenkreuz sofort, nicht erst nach der ersten Mausbewegung (die
        // Cursor-Rechtecke greifen erst, wenn sich die Maus bewegt).
        NSCursor.crosshair.set()

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
        NSCursor.arrow.set()
        // Fokus zurück, sonst bleibt Tippi vorne und verdeckt die Arbeit.
        previousApp?.activate()
        previousApp = nil
    }
}

// MARK: - Fenster

/// Borderless, but allowed to become key so ESC reaches `SelectionView`.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Die Auswahl-Ansicht

/// Nimmt Maus und Tasten entgegen und ordnet drei Ebenen übereinander:
/// das Standbild mit Abdunklung und Rahmen (`SelectionCanvas`, reine
/// CALayer), darüber Hinweis- und Maß-Kapsel (SwiftUI-Glas).
///
/// **Warum CALayer statt `draw(_:)`:** Vorher wurde bei **jeder** Mausbewegung
/// das komplette Standbild neu gezeichnet — auf einem 3440-px-Monitor ruckelt
/// das Aufziehen. Jetzt liegt das Bild einmal als Ebeneninhalt fest, bewegt
/// werden nur Abdunklung und Rahmen.
private final class SelectionView: NSView {

    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let canvas = SelectionCanvas()
    private let sizeModel = SizeBadgeModel()
    private var hintHost: NSHostingView<OverlayHint>?
    private var badgeHost: NSHostingView<SizeBadge>?

    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(frozenImage: CGImage?, scale: CGFloat, hintTopInset: CGFloat?) {
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.configure(image: frozenImage, scale: scale)
        addSubview(canvas)

        let badge = NSHostingView(rootView: SizeBadge(model: sizeModel))
        badge.isHidden = true
        addSubview(badge)
        badgeHost = badge

        if let hintTopInset {
            let hint = NSHostingView(rootView: OverlayHint())
            let size = hint.fittingSize
            hint.frame = NSRect(x: (bounds.width - size.width) / 2,
                                y: bounds.height - hintTopInset - size.height,
                                width: size.width, height: size.height)
            addSubview(hint)
            hintHost = hint
        }
    }

    /// Alle Klicks gehören der Auswahl — auch über Hinweis und Maß-Kapsel.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selectionRect: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    private func update() {
        let rect = selectionRect
        canvas.show(selection: rect)
        guard let rect, let badgeHost else {
            badgeHost?.isHidden = true
            return
        }
        sizeModel.text = "\(Int(rect.width)) × \(Int(rect.height))"
        let size = badgeHost.fittingSize
        // Unter der Auswahl rechtsbündig wie beim macOS-Bildschirmfoto; reicht
        // der Platz nicht, darüber.
        var origin = NSPoint(x: rect.maxX - size.width, y: rect.minY - size.height - 8)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + 8 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        badgeHost.frame = NSRect(origin: origin, size: size)
        badgeHost.isHidden = false
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        // Wer zieht, hat den Hinweis gelesen.
        if let hintHost {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                hintHost.animator().alphaValue = 0
            }
        }
        update()
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        update()
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil; current = nil; update() }
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

// MARK: - Standbild, Abdunklung, Rahmen

/// Reine Ebenen-Ansicht (layer-hosting, ohne Unteransichten).
private final class SelectionCanvas: NSView {

    /// Deutlich genug, dass der Wechsel zum Standbild auffällt, hell genug,
    /// dass man den Text zum Zielen noch liest.
    static let dimAlpha: CGFloat = 0.38

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(image: CGImage?, scale: CGFloat) {
        guard let root = layer else { return }
        root.contentsScale = scale

        // Ohne Standbild (Zuordnung fehlgeschlagen) bleibt die Ebene leer —
        // dann wirkt das Overlay wie früher durchsichtig über dem echten Schirm.
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.frame = bounds

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(Self.dimAlpha).cgColor

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOpacity = 0.55
        borderLayer.shadowRadius = 2
        borderLayer.shadowOffset = .zero

        cornerLayer.fillColor = nil
        cornerLayer.strokeColor = NSColor.white.cgColor
        cornerLayer.lineWidth = 3
        cornerLayer.lineCap = .round
        cornerLayer.lineJoin = .round
        cornerLayer.shadowColor = NSColor.black.cgColor
        cornerLayer.shadowOpacity = 0.45
        cornerLayer.shadowRadius = 2
        cornerLayer.shadowOffset = .zero

        for sub in [imageLayer, dimLayer, borderLayer, cornerLayer] {
            sub.contentsScale = scale
            sub.frame = bounds
            root.addSublayer(sub)
        }
        show(selection: nil)
    }

    /// Abdunklung überall außer in der Auswahl; Rahmen und Eckwinkel nur mit Auswahl.
    func show(selection rect: NSRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // keine Ebenen-Animation beim Ziehen

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let rect { dim.addRect(rect) }       // even-odd: Auswahl bleibt hell
        dimLayer.path = dim

        if let rect, rect.width >= 1, rect.height >= 1 {
            borderLayer.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            cornerLayer.path = Self.corners(around: rect)
        } else {
            borderLayer.path = nil
            cornerLayer.path = nil
        }
        CATransaction.commit()
    }

    /// Vier Eckwinkel knapp außerhalb der Auswahl, wie ein Sucher.
    private static func corners(around rect: NSRect) -> CGPath {
        let path = CGMutablePath()
        let outer = rect.insetBy(dx: -2, dy: -2)
        let arm = min(14, outer.width / 2, outer.height / 2)
        let points: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: outer.minX, y: outer.minY), 1, 1),
            (CGPoint(x: outer.maxX, y: outer.minY), -1, 1),
            (CGPoint(x: outer.minX, y: outer.maxY), 1, -1),
            (CGPoint(x: outer.maxX, y: outer.maxY), -1, -1),
        ]
        for (corner, dx, dy) in points {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}

// MARK: - Glas-Kapseln (SwiftUI)

private final class SizeBadgeModel: ObservableObject {
    @Published var text = ""
}

/// Maße der Auswahl — hilft beim genauen Treffen kleiner Textstellen.
private struct SizeBadge: View {
    @ObservedObject var model: SizeBadgeModel

    var body: some View {
        Text(model.text)
            .font(FamilyTheme.font(11, weight: .semibold).monospacedDigit())
            .foregroundStyle(FamilyTheme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .tippiGlass(in: Capsule())
            .fixedSize()
    }
}

/// Hinweis oben in der Mitte: zeigt, dass die Auswahl bereit ist und wie man
/// wieder herauskommt.
private struct OverlayHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "ocr.overlay.hint"))
                .font(FamilyTheme.font(13, weight: .medium))
        }
        .foregroundStyle(FamilyTheme.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .tippiGlass(in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(12)            // Platz für den Schatten
        .fixedSize()
    }
}
