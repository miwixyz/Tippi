import SwiftUI

// Glas-Effekte der App-Familie, übernommen aus Porter (13.11.2026, Michael: „Mach die
// Optikoptimierung auch mit Tippi, TippAI, Gnotchi und Kalli“). Vorbild: vividsites
// „Liquid Glass Pill“ (Lichtkante folgt dem Zeiger, Glanz oben, Bauch unten, Stauchen beim
// Drücken) und „Tab Indicator“ (gleitender Hover-Schatten, Pille dehnt sich auf zwei Federn).
// Prinzip in SwiftUI nachgebaut, Farben aus FamilyTheme. Die Brechung übernimmt Apples Glas.

// MARK: - Rechenteile (getestet in GlassEffectsTests)

enum GlassMotion {
    /// Welche Feder eine Kante der gleitenden Pille bekommt.
    enum EdgeRole: Equatable { case lead, trail, even }

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let lead = Animation.spring(response: 0.2, dampingFraction: 0.8)
    static let trail = Animation.spring(response: 0.46, dampingFraction: 0.74)
    static let hover = Animation.spring(response: 0.26, dampingFraction: 0.86)

    /// In Fahrtrichtung vorn liegende Kante straff, hintere weich; ohne Richtung beide gleich.
    /// So dehnt sich die Pille zum Ziel hin und zieht sich dort zusammen.
    static func role(direction: Int, rightEdge: Bool) -> EdgeRole {
        switch direction {
        case 1: rightEdge ? .lead : .trail
        case -1: rightEdge ? .trail : .lead
        default: .even
        }
    }

    static func animation(_ role: EdgeRole) -> Animation {
        switch role {
        case .lead: lead
        case .trail: trail
        case .even: spring
        }
    }

    /// +1 nach rechts, -1 nach links, 0 ohne Wechsel oder ohne bekannten Ausgangspunkt.
    static func direction(from old: Int?, to new: Int?) -> Int {
        guard let old, let new, old != new else { return 0 }
        return new > old ? 1 : -1
    }
}

// MARK: - Hover-Schatten, der zwischen Elementen gleitet

private let ghostSpace = "familyGlassGhost"

private struct GhostFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    /// Meldet dieses Element beim umgebenden `glassGhostHost`. Gesperrte Elemente melden nichts.
    func glassGhostItem(_ enabled: Bool = true) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: GhostFrames.self,
                                       value: enabled ? [geometry.frame(in: .named(ghostSpace))] : [])
            }
        }
    }

    /// Weicher Schatten unter dem Element, über dem der Zeiger steht. Erscheint an Ort und
    /// Stelle und gleitet danach von Element zu Element. `radius` groß = Kapsel.
    func glassGhostHost(tint: Color = FamilyTheme.textPrimary, opacity: Double = 0.07,
                        radius: CGFloat = 99) -> some View {
        modifier(GhostHost(tint: tint, opacity: opacity, radius: radius))
    }
}

private struct GhostHost: ViewModifier {
    let tint: Color
    let opacity: Double
    let radius: CGFloat
    @State private var pointer: CGPoint?

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(ghostSpace))
            .backgroundPreferenceValue(GhostFrames.self) { frames in
                if let pointer, let frame = frames.first(where: { $0.insetBy(dx: -2, dy: -4).contains(pointer) }) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint.opacity(opacity))
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .animation(GlassMotion.hover, value: frame)
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): pointer = point
                case .ended: pointer = nil
                }
            }
    }
}

// MARK: - Drücken

/// Drücken: breiter und flacher, beim Loslassen federt das Element zurück („Liquid Glass Pill“).
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: configuration.isPressed ? 1.08 : 1, y: configuration.isPressed ? 0.86 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08)
                       : .spring(response: 0.32, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPressStyle {
    static var glassPress: GlassPressStyle { GlassPressStyle() }
}

// MARK: - Gleitende Pille (Ersatz für den Segment-Umschalter)

private let pillSpace = "familySlidingPill"

private struct PillFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Farben der gleitenden Auswahl. `.family` = Karten-Pille mit Akzent auf hellem Grund;
/// eigene Werte z. B. für dunkle Flächen (Gnotchis Insel).
struct SlidingPickerPalette {
    var selectedText: Color = FamilyTheme.accent
    var text: Color = FamilyTheme.textSecondary
    var ghost: Color = FamilyTheme.textPrimary
    var ghostOpacity: Double = 0.06
    /// `nil` = Karten-Pille (`SlidingPillShape`), sonst schlichte Fläche in dieser Farbe.
    var pillFill: Color?

    static let family = SlidingPickerPalette()
}

/// Auswahl in einer vertieften Kapsel-Spur; die Pille der Auswahl gleitet auf zwei Federn
/// (dehnt sich zum Ziel), ein Hover-Schatten gleitet über die übrigen Einträge.
/// Wechsel von außen (Tastatur, Menü) gleiten ebenso, weil die Richtung aus dem zuletzt
/// gezeigten Eintrag berechnet wird.
struct SlidingPicker<Value: Hashable, Label: View>: View {
    let options: [Value]
    @Binding var selection: Value
    var height: CGFloat = 24
    var accessibilityTitle: Text?
    /// Eckenradius von Pille und Hover-Schatten; groß = Kapsel.
    var cornerRadius: CGFloat = 99
    /// Vertiefte Spur hinter den Einträgen.
    var track = true
    var spacing: CGFloat = 2
    var segmentPadding: CGFloat = 10
    var palette = SlidingPickerPalette.family
    let label: (Value, Bool) -> Label

    @State private var hovered: Int?
    @State private var shown: Int?
    @Environment(\.colorScheme) private var scheme

    init(_ options: [Value], selection: Binding<Value>, height: CGFloat = 24,
         accessibilityTitle: Text? = nil, cornerRadius: CGFloat = 99, track: Bool = true,
         spacing: CGFloat = 2, segmentPadding: CGFloat = 10, palette: SlidingPickerPalette = .family,
         @ViewBuilder label: @escaping (Value, Bool) -> Label) {
        self.options = options
        _selection = selection
        self.height = height
        self.accessibilityTitle = accessibilityTitle
        self.cornerRadius = cornerRadius
        self.track = track
        self.spacing = spacing
        self.segmentPadding = segmentPadding
        self.palette = palette
        self.label = label
    }

    private var selectedIndex: Int? { options.firstIndex(of: selection) }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, value in
                segment(index, value)
            }
        }
        .coordinateSpace(.named(pillSpace))
        .backgroundPreferenceValue(PillFrames.self) { frames in
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    hoverGhost(frames)
                    pill(frames, trackWidth: geometry.size.width)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
        }
        .padding(track ? 2 : 0)
        .background {
            if track {
                Capsule().fill(FamilyTheme.textPrimary.opacity(scheme == .dark ? 0.10 : 0.06))
                    .overlay { Capsule().strokeBorder(FamilyTheme.cardStroke.opacity(0.6), lineWidth: 0.5) }
            }
        }
        .onAppear { shown = selectedIndex }
        .onChange(of: selection) { shown = selectedIndex }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle ?? Text(verbatim: ""))
    }

    private func segment(_ index: Int, _ value: Value) -> some View {
        let selected = index == selectedIndex
        return Button {
            selection = value
        } label: {
            label(value, selected)
                .foregroundStyle(selected ? palette.selectedText : palette.text)
                .padding(.horizontal, segmentPadding)
                .frame(minHeight: height)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.glassPress)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PillFrames.self, value: [index: geometry.frame(in: .named(pillSpace))])
            }
        }
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func pill(_ frames: [Int: CGRect], trackWidth: CGFloat) -> some View {
        if let index = selectedIndex, let frame = frames[index] {
            let direction = GlassMotion.direction(from: shown, to: index)
            pillShape
                .padding(.leading, frame.minX)
                .animation(GlassMotion.animation(GlassMotion.role(direction: direction, rightEdge: false)),
                           value: frame.minX)
                .padding(.trailing, max(0, trackWidth - frame.maxX))
                .animation(GlassMotion.animation(GlassMotion.role(direction: direction, rightEdge: true)),
                           value: frame.maxX)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var pillShape: some View {
        if let fill = palette.pillFill {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
        } else {
            SlidingPillShape(dark: scheme == .dark, cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    private func hoverGhost(_ frames: [Int: CGRect]) -> some View {
        if let hovered, hovered != selectedIndex, let frame = frames[hovered] {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.ghost.opacity(palette.ghostOpacity * (scheme == .dark ? 1.33 : 1)))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX)
                .animation(GlassMotion.hover, value: frame)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
        }
    }
}

/// Die Pille der Auswahl: Kartenfläche mit Hauch Akzent, Glanz oben, Lichtkante, weicher Schatten.
struct SlidingPillShape: View {
    let dark: Bool
    var cornerRadius: CGFloat = 99

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(FamilyTheme.card)
            .overlay { shape.fill(FamilyTheme.accent.opacity(dark ? 0.16 : 0.07)) }
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.07 : 0.5), .white.opacity(0)],
                                          startPoint: .top, endPoint: .center))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.18 : 0.95),
                                                           Color.black.opacity(dark ? 0.1 : 0.08)],
                                                  startPoint: .top, endPoint: .bottom),
                                   lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(dark ? 0.5 : 0.10), radius: 1, y: 0.5)
            .shadow(color: .black.opacity(dark ? 0.4 : 0.10), radius: 6, y: 3)
    }
}
