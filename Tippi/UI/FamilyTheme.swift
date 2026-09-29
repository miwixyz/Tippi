// FamilyTheme.swift — Design-Tokens der App-Familie (Tippi, Kalli, TippAI, Qotti)
//
// Quelle der Wahrheit: „App-Familie Design-System.md“ im selben Ordner (Vault).
// Stand 2026-09-29. In ein App-Projekt KOPIEREN und dort nur `FamilyTheme.app`
// setzen — die Werte hier nicht pro App abwandeln, sonst driftet die Familie.
//
// Plattformen: macOS 14+/iOS 17+ (Farben, Verlauf, Karten). Liquid Glass ab
// macOS/iOS 26 über `glassEffect`, darunter ein Material-Fallback.

import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Hell/Dunkel-Farben

extension Color {
    /// Farbe mit getrenntem Wert für Hell und Dunkel, als echte dynamische Systemfarbe
    /// (reagiert auf NSApp.appearance / Trait-Wechsel ohne Neuzeichnen von Hand).
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

// MARK: - Tokens

enum FamilyTheme {

    /// Welche App — bestimmt nur den Akzent. Alles andere ist für alle gleich.
    enum App { case tippi, kalli, tippAI, qotti }

    /// In jeder App genau einmal setzen (z. B. im App-Einstieg).
    nonisolated(unsafe) static var app: App = .kalli

    // Akzente „Schiefer“ (Variante B, Michael 29.09.): aus #56607E abgeleitet, Farbton 208–242°, gedämpft, Kontrast geprüft (WCAG ≥ 4,5 : 1
    // für Text auf Weiß bzw. auf der dunklen Karte, gerechnet 2026-09-29).
    static var accent: Color {
        switch app {
        case .tippi:  Color(light: 0x3E5998, dark: 0x98AEE1)   // Schieferblau
        case .kalli:  Color(light: 0x3E4D98, dark: 0x98A4E1)   // Schieferindigo
        case .tippAI: Color(light: 0x413E98, dark: 0x9B98E1)   // Schieferviolett
        case .qotti:  Color(light: 0x3E6E98, dark: 0x98BFE1)   // Schiefer-Himmelblau
        }
    }
    /// Füllung für Flächen mit WEISSER Schrift (`.borderedProminent`, gefüllte Kapseln).
    /// Hell = `accent`. Dunkel ein satterer Ton: Der helle Dunkelmodus-Akzent ist für
    /// Text/Symbole gedacht, Weiß darauf hätte nur 2,2 : 1 (Tippi, gemessen 29.09.).
    /// Diese Werte halten Weiß ≥ 4,6 : 1. Einsatz: `.tint(FamilyTheme.accentFill)`.
    static var accentFill: Color {
        switch app {
        case .tippi:  Color(light: 0x3E5998, dark: 0x5172BD)
        case .kalli:  Color(light: 0x3E4D98, dark: 0x5C6DC1)
        case .tippAI: Color(light: 0x413E98, dark: 0x6B67C5)
        case .qotti:  Color(light: 0x3E6E98, dark: 0x4179AA)
        }
    }

    /// Gemeinsamer Familienton (Iris) — für Übergreifendes: Website, Icons, Marketing.
    static let iris = Color(light: 0x3E5398, dark: 0x98A9E1)

    /// Text/Symbol AUF einer Akzentfläche (aktive Kapsel, „heute“). Hell weiß, dunkel
    /// dunkel — weiß auf dem hellen Dunkelmodus-Akzent wäre kaum lesbar (im Rendering-
    /// Test 2026-09-29 gesehen). Nie `.white` fest verdrahten.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D1019)

    // Flächen
    static let backgroundTop    = Color(light: 0xF3F5F9, dark: 0x0D1019)
    static let backgroundMiddle = Color(light: 0xE7E9F1, dark: 0x161A25)
    static let backgroundBottom = Color(light: 0xD9DDE8, dark: 0x1F2433)
    /// Feste Inhaltsfläche (Karte, Editor, Liste). Nie transparent.
    static let card        = Color(light: 0xFFFFFF, dark: 0x1B2130)
    static let cardStroke  = Color(light: 0xE2E5EE, dark: 0x2A3142)
    /// Tönung für große Glasflächen (siehe `familyTintedGlass`). Mitte des Verlaufs,
    /// 78 % Deckkraft — ruhig, aber das Glas bleibt als Glas erkennbar.
    static let glassTint = Color(light: 0xF3F5F9, dark: 0x161A25).opacity(0.78)
    /// Hauptknopf der schwebenden Leiste („+“): dunkel im Hellen, hell im Dunklen.
    static let primaryFill = Color(light: 0x1E2433, dark: 0xECEFF6)
    static let onPrimary   = Color(light: 0xFFFFFF, dark: 0x1E2433)

    // Text
    static let textPrimary   = Color(light: 0x1E2433, dark: 0xECEFF6)
    static let textSecondary = Color(light: 0x56607E, dark: 0xA3ACC8)   // Michaels Referenzton

    // Status (sparsam — Farbe trägt nie allein die Bedeutung)
    static let success = Color(light: 0x1F8A6B, dark: 0x6FE0C1)
    static let warning = Color(light: 0xB25E09, dark: 0xF5B35C)
    static let danger  = Color(light: 0xC23B4E, dark: 0xFF8A9A)

    // MARK: Schrift — Plus Jakarta Sans (Michael, 2026-09-29), SIL OFL 1.1
    //
    // Datei `PlusJakartaSans-Variable.ttf` (eine Datei, alle Stärken) ins App-Bundle
    // legen und beim Start einmal `FamilyTheme.registerFonts()` aufrufen. `relativeTo:`
    // hält Dynamic Type/große Systemschrift am Leben.
    static let fontFamily = "Plus Jakarta Sans"

    static func font(_ size: CGFloat, weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(fontFamily, size: size, relativeTo: style).weight(weight)
    }

    /// Ersatz für `.font(.caption)`, `.font(.headline)` usw.: gleiche Größe wie der
    /// Apple-Textstil der Plattform, aber in Plus Jakarta Sans. Auf iPhone/iPad wächst
    /// sie mit Dynamic Type (`relativeTo:`). Überschrift-Stile sind SemiBold wie bei Apple.
    static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let size: CGFloat
        let defaultWeight: Font.Weight
        #if os(macOS)
        switch style {
        case .largeTitle: size = 26; defaultWeight = .regular
        case .title: size = 22; defaultWeight = .regular
        case .title2: size = 17; defaultWeight = .regular
        case .title3: size = 15; defaultWeight = .regular
        case .headline: size = 13; defaultWeight = .semibold
        case .subheadline: size = 11; defaultWeight = .regular
        case .callout: size = 12; defaultWeight = .regular
        case .footnote, .caption, .caption2: size = 10; defaultWeight = .regular
        default: size = 13; defaultWeight = .regular
        }
        #else
        switch style {
        case .largeTitle: size = 34; defaultWeight = .regular
        case .title: size = 28; defaultWeight = .regular
        case .title2: size = 22; defaultWeight = .regular
        case .title3: size = 20; defaultWeight = .regular
        case .headline: size = 17; defaultWeight = .semibold
        case .subheadline: size = 15; defaultWeight = .regular
        case .callout: size = 16; defaultWeight = .regular
        case .footnote: size = 13; defaultWeight = .regular
        case .caption: size = 12; defaultWeight = .regular
        case .caption2: size = 11; defaultWeight = .regular
        default: size = 17; defaultWeight = .regular
        }
        #endif
        return font(size, weight: weight ?? defaultWeight, relativeTo: style)
    }

    /// Registriert die Schriftdatei aus dem App-Bundle. Gibt zurück, ob es geklappt hat —
    /// ohne Registrierung fällt SwiftUI still auf die Systemschrift zurück.
    @discardableResult
    static func registerFonts(bundle: Bundle = .main) -> Bool {
        guard let url = bundle.url(forResource: "PlusJakartaSans-Variable", withExtension: "ttf") else {
            return false
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // „bereits registriert“ zählt als Erfolg.
        return ok || (error?.takeRetainedValue()).map { CFErrorGetCode($0) == 105 } == true
    }

    // Formen (Punkte)
    enum Radius {
        static let card: CGFloat = 28     // große Inhaltskarten
        static let tile: CGFloat = 20     // Kacheln, Listenzeilen-Gruppen
        static let field: CGFloat = 14    // Eingabefelder, kleine Karten
    }
    // Abstände: 4-Punkt-Raster
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 32
    }

    /// Hintergrundverlauf „Schiefer“: kühles Blaugrau. Fest, nicht transparent.
    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMiddle, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Bausteine

extension View {
    /// Fenster-/Bildschirmhintergrund der Familie.
    func familyBackground() -> some View {
        background(FamilyTheme.backgroundGradient.ignoresSafeArea())
    }

    /// Feste Inhaltskarte: weiß bzw. dunkles Violett, großer Radius, weicher Schatten.
    func familyCard(radius: CGFloat = FamilyTheme.Radius.card) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(FamilyTheme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8)
                }
                .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(0.10), radius: 18, y: 8)
        }
    }

    /// Schiefer-Tönung ÜBER dem Glas einer großen Fläche (Popover, Vollbild-Hinweis).
    /// Ohne sie scheint das Schreibtischbild voll durch und färbt alles ein — in Kalli
    /// 0.6.0-Test gesehen: pinkes Hintergrundbild → rosa Popover (Michael, 29.09.).
    /// Entspricht der Vorschau (Fläche mit ca. 80 % Deckkraft über Unschärfe).
    func familyTintedGlass<S: Shape>(in shape: S) -> some View {
        background(shape.fill(FamilyTheme.glassTint)).familyGlass(in: shape)
    }

    /// Glas-Element (Kapsel, runder Knopf, schwebende Leiste). NUR für Bedienelemente,
    /// die über Inhalt schweben — nie für Inhaltsflächen (siehe Design-System, Regel G1).
    @ViewBuilder
    func familyGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(.white.opacity(0.35), lineWidth: 0.8) }
        }
    }
}

// MARK: - Neutraler Glas-Knopf

/// Glas-Kapsel bzw. runder Glas-Knopf wie in der Vorschau: NEUTRAL, Schrift in
/// `textPrimary`. Apples `.buttonStyle(.glass)` übernimmt dagegen die Akzentfarbe
/// der App und füllt jeden Knopf blau (Kalli 0.6.0-Test, 29.09.) — für eine Leiste
/// aus mehreren Knöpfen ist das zu laut. Den Akzent trägt nur der eine aktive Knopf.
struct FamilyGlassButtonStyle: ButtonStyle {
    enum Form { case circle, capsule }
    var form: Form = .capsule
    /// Durchmesser bzw. Mindesthöhe in Punkten.
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        FamilyGlassButtonLabel(configuration: configuration, form: form, size: size)
    }
}

private struct FamilyGlassButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let form: FamilyGlassButtonStyle.Form
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let label = configuration.label
            .foregroundStyle(FamilyTheme.textPrimary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
            .contentShape(Rectangle())
        switch form {
        case .circle:
            label.frame(width: size, height: size).familyGlass(in: Circle())
        case .capsule:
            label.padding(.horizontal, size * 0.42).frame(minHeight: size).familyGlass(in: Capsule())
        }
    }
}

extension ButtonStyle where Self == FamilyGlassButtonStyle {
    static var familyGlass: FamilyGlassButtonStyle { FamilyGlassButtonStyle() }
    static func familyGlass(_ form: FamilyGlassButtonStyle.Form, size: CGFloat = 26) -> FamilyGlassButtonStyle {
        FamilyGlassButtonStyle(form: form, size: size)
    }
}
