import SwiftUI

/// Oberfläche schwebender Tippi-Elemente (Popup, Emoji, Auswahl-Leiste, Toast, Aufnahme-Anzeige, Übersetzen).
/// Eine Quelle für Karte, Rand und Schatten, damit alle gleich aussehen (Familien-Design „Schiefer“).
/// Listen und Fenster sind feste Karten, Pille und Leiste getöntes Glas (Familienregel: Glas nur für Bedienelemente,
/// die über Inhalt schweben).

private struct FloatingPanel<S: InsettableShape>: ViewModifier {
    let shape: S
    var shadow = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(FamilyTheme.card))
            .clipShape(shape)
            .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
            .shadow(color: .black.opacity(shadow ? 0.12 : 0), radius: 12, y: 4)
    }
}

private struct FloatingControl<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .familyTintedGlass(in: shape)
            .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }
}

extension View {
    /// Feste Karte für Listen und Fenster.
    func floatingPanel(radius: CGFloat = FamilyTheme.Radius.tile) -> some View {
        modifier(FloatingPanel(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }

    /// Pille (Toast, Aufnahme-Anzeige): Kapsel mit Schatten.
    func floatingPill() -> some View {
        modifier(FloatingControl(shape: Capsule()))
    }

    /// Leiste und kleine Textbox: abgerundetes Rechteck mit Schatten.
    func floatingBar(radius: CGFloat = FamilyTheme.Radius.field) -> some View {
        modifier(FloatingControl(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
}
