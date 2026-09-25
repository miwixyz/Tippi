import AppKit
import SwiftUI

/// Grauer Vorschlag der Autovervollständigung direkt hinter dem Cursor.
///
/// Gleiche Grundregel wie `EmojiSuggestionPanel`: `NonKeyPanel`, wird nie
/// Key-Fenster — der Nutzer tippt in einer *anderen* App weiter. Anders als die
/// Emoji-Liste nimmt dieses Panel auch keine Klicks an (`ignoresMouseEvents`):
/// ein Klick geht an die App darunter und verwirft den Vorschlag (Design:
/// „jede andere Taste, Esc, Klick oder App-Wechsel verwirft").
@MainActor
final class AutocompleteSuggestionPanel {
    private var panel: NSPanel?

    var isOpen: Bool { panel != nil }

    /// `caret` in AppKit-Bildschirmkoordinaten (Ursprung unten links), wie
    /// `TextCapture.boundsForSelection` sie liefert.
    func show(_ suggestion: String, caret: CGRect) {
        close()
        let fontSize = AutocompleteGeometry.fontSize(forCaretHeight: caret.height)
        let hosting = ClickableHostingView(rootView: AutocompleteSuggestionView(text: suggestion, fontSize: fontSize))
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: caret.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
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
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct AutocompleteSuggestionView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(text.trimmingCharacters(in: .whitespaces))
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            // Nennt die Taste, die übernimmt — sonst sieht der graue Text wie
            // ein Anzeigefehler aus.
            Text("⇥")
                .font(.system(size: max(9, fontSize * 0.7), weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .tippiGlass(in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
