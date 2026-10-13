import AppKit
import SwiftUI

/// Vorschlag der Autovervollständigung als grauer Text direkt hinter dem
/// Cursor (ohne Hintergrund, siehe `AutocompleteSuggestionView`).
///
/// Gleiche Grundregel wie `EmojiSuggestionPanel`: `NonKeyPanel`, wird nie
/// Key-Fenster — der Nutzer tippt in einer *anderen* App weiter. Anders als die
/// Emoji-Liste nimmt dieses Panel auch keine Klicks an (`ignoresMouseEvents`):
/// ein Klick geht an die App darunter und verwirft den Vorschlag (Design:
/// „jede andere Taste, Esc, Klick oder App-Wechsel verwirft").
///
/// Ein sichtbares Panel wird beim Weitertippen und Wort-für-Wort **an Ort und
/// Stelle aktualisiert**, nicht neu gebaut — sonst blendete die Kapsel bei
/// jedem Zeichen neu ein.
@MainActor
final class AutocompleteSuggestionPanel {
    private var panel: NSPanel?
    private var hosting: ClickableHostingView<AutocompleteSuggestionView>?

    static let fadeInDuration: TimeInterval = 0.12
    static let fadeOutDuration: TimeInterval = 0.1

    /// „⇥ Wort · ⇧⇥ alles" aus den konfigurierten Tasten.
    static func keyHint(_ bindings: AutocompleteKeyBindings) -> String {
        String(format: String(localized: "autocomplete.keyHint"),
               bindings.nextWord.displayString, bindings.wholeSuggestion.displayString)
    }

    /// `caret` in AppKit-Bildschirmkoordinaten (Ursprung unten links), wie
    /// `TextCapture.boundsForSelection` sie liefert. `animated` = weich
    /// einblenden; gilt nur, wenn gerade keine Kapsel sichtbar ist.
    func show(_ suggestion: String, caret: CGRect, fontSize: CGFloat, hint: AutocompleteSuggestionView.Hint?, animated: Bool) {
        let view = AutocompleteSuggestionView(text: suggestion, fontSize: fontSize, hint: hint, animateIn: animated)
        let panel: NSPanel
        let hosting: ClickableHostingView<AutocompleteSuggestionView>
        let isNew: Bool
        if let existingPanel = self.panel, let existingHosting = self.hosting {
            existingHosting.rootView = view
            panel = existingPanel
            hosting = existingHosting
            isNew = false
        } else {
            hosting = ClickableHostingView(rootView: view)
            hosting.sizingOptions = [.intrinsicContentSize]
            panel = Self.makePanel(height: caret.height)
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
            isNew = true
        }

        panel.layoutIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)

        // Direkt hinter dem Cursor, vertikal auf die Zeile zentriert.
        var origin = NSPoint(x: caret.maxX + 1, y: caret.midY - size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)

        guard isNew else { return }
        // Einblenden als reine Deckkraft — auch bei „Bewegung reduzieren"
        // zulässig; die kleine Skalierung dazu macht die View selbst und
        // lässt sie dann weg.
        panel.alphaValue = animated ? 0 : 1
        panel.orderFrontRegardless()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                panel.animator().alphaValue = 1
            }
        }
    }

    /// `animated` = weich ausblenden. Das Panel ist sofort vergessen; ein
    /// neuer Vorschlag baut ein neues. Weggeräumt wird über einen eigenen
    /// Zeitpunkt statt über den Abschluss der Animation — der kommt nicht in
    /// jedem Fall (ToastWindow, 2026-09-13: Fenster blieb stehen).
    func close(animated: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        hosting = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.fadeOutDuration * 1_000_000_000))
            panel.orderOut(nil)
        }
    }

    private static func makePanel(height: CGFloat) -> NSPanel {
        let panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        panel.appearance = AppearanceSettings.panelAppearance()
        return panel
    }
}

/// Vorschlag als grauer Text direkt im Textfluss, ohne Hintergrund und ohne
/// Linie — wie Apples eigene Vorschläge beim Tippen; dahinter eine kleine
/// Tastenkappe mit der Wort-Taste. Bis 2.27.0 eine Glas-Kapsel: Auf hellem wie
/// dunklem Dokument nahm das Glas den Hintergrund an, der graue Text darauf war
/// kaum lesbar. Eine Unterstreichung in Akzentfarbe war Michael „altmodisch"
/// (beides 2026-10-13). Vorschläge gibt es nur am Zeilenende, der Text
/// überdeckt also nichts.
struct AutocompleteSuggestionView: View {
    /// `key` steht auf der Kappe (z. B. „⇥"), `label` liest VoiceOver vor
    /// („⇥ Wort · ⇧⇥ alles").
    struct Hint: Equatable {
        let key: String
        let label: String
    }

    /// Fester Mittelton statt `.secondary`: Das Panel kennt nur Tippis
    /// Erscheinungsbild, nicht den Hintergrund des Dokuments — Mittelgrau ist
    /// auf Weiß wie auf Fast-Schwarz lesbar und sieht trotzdem nach Vorschlag aus.
    static let ghostColor = Color(white: 0.5)

    let text: String
    let fontSize: CGFloat
    /// Tastenhinweis — `nil`, wenn in den Einstellungen ausgeblendet.
    let hint: Hint?

    /// Ein führendes Leerzeichen bleibt als genau eines stehen — ohne Kapsel
    /// trennt sonst nichts den Vorschlag vom Wort davor („dennpassiert?").
    static func displayText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return text.first?.isWhitespace == true ? " " + trimmed : trimmed
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared: Bool

    init(text: String, fontSize: CGFloat, hint: Hint?, animateIn: Bool) {
        self.text = text
        self.fontSize = fontSize
        self.hint = hint
        // Beim Aktualisieren an Ort und Stelle behält SwiftUI den Zustand —
        // der Startwert zählt nur beim ersten Anzeigen.
        _appeared = State(initialValue: !animateIn)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.55) {
            Text(Self.displayText(text))
                .font(.system(size: fontSize))
                .foregroundStyle(Self.ghostColor)
                .lineLimit(1)
                .fixedSize()
            if let hint {
                // Nennt die Taste, die übernimmt — sonst sieht der graue Text
                // wie ein Anzeigefehler aus.
                Text(hint.key)
                    .font(.system(size: max(9, fontSize * 0.68), weight: .medium))
                    .foregroundStyle(Self.ghostColor)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, max(4, fontSize * 0.35))
                    .padding(.vertical, max(1, fontSize * 0.08))
                    .overlay(RoundedRectangle(cornerRadius: max(3, fontSize * 0.3), style: .continuous)
                        .strokeBorder(Self.ghostColor.opacity(0.6), lineWidth: 1))
                    .accessibilityLabel(hint.label)
            }
        }
        .padding(.trailing, 2)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.94, anchor: .leading)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: AutocompleteSuggestionPanel.fadeInDuration + 0.04)) { appeared = true }
        }
    }
}
