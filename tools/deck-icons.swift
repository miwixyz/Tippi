// Draws the Stream Deck plugin icons (docs/SECURE-DESIGN-stream-deck.md) as PNG – the same family style as Gnotchi's plugin
// (Michael 17.11.: light glyphs on a cool dark grey, accent slate iris #98A9E1, text on top, glyph below, one image per state).
// Recording is the one warm colour (soft red), so a running dictation is obvious from across the desk.
// Run once, the result is committed:
//   swiftc -O tools/deck-icons.swift -o /tmp/tippi-deck-icons && /tmp/tippi-deck-icons TippiDeck/dev.mwlr.tippi.deck.sdPlugin/imgs
// No emoji, no SF Symbols (not allowed outside Apple UIs) – every glyph is drawn here.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let ink = NSColor(red: 0xEE / 255, green: 0xEF / 255, blue: 0xF4 / 255, alpha: 1)
let inkDim = NSColor(red: 0xEE / 255, green: 0xEF / 255, blue: 0xF4 / 255, alpha: 0.32)
let accent = NSColor(red: 0x98 / 255, green: 0xA9 / 255, blue: 0xE1 / 255, alpha: 1)
let red = NSColor(red: 0xF0 / 255, green: 0x7A / 255, blue: 0x6E / 255, alpha: 1)
let white = NSColor(white: 1, alpha: 1)

enum Glyph {
    case mic, mail, voiceNote, wand, popup, translate, emoji, notes, quickNote, screenText, password, pause, resume
    case autocomplete, language, toggle
}

/// Box 0…1 → pixels; y thought from the top, CoreGraphics counts from the bottom.
struct Canvas {
    let box: CGRect
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: box.minX + x * box.width, y: box.maxY - y * box.height) }
    func r(_ v: CGFloat) -> CGFloat { v * box.width }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        let top = p(x, y)
        return NSRect(x: top.x, y: top.y - r(h), width: r(w), height: r(h))
    }
}

func stroke(_ path: NSBezierPath, _ c: Canvas, width: CGFloat = 0.075) {
    path.lineWidth = c.r(width)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func line(_ c: Canvas, _ pts: [(CGFloat, CGFloat)], width: CGFloat = 0.075) {
    let b = NSBezierPath()
    b.move(to: c.p(pts[0].0, pts[0].1))
    for q in pts.dropFirst() { b.line(to: c.p(q.0, q.1)) }
    stroke(b, c, width: width)
}

func text(_ s: String, _ c: Canvas, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .bold) {
    let attr = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: c.r(size), weight: weight),
                                                          .foregroundColor: color])
    let sz = attr.size()
    let center = c.p(x, y)
    attr.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
}

func micBody(_ c: Canvas) {
    NSBezierPath(roundedRect: c.rect(0.36, 0.10, 0.28, 0.48), xRadius: c.r(0.14), yRadius: c.r(0.14)).fill()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c.p(0.50, 0.40), radius: c.r(0.25), startAngle: 200, endAngle: 340, clockwise: false)
    stroke(arc, c)
    line(c, [(0.50, 0.66), (0.50, 0.84)])
    line(c, [(0.36, 0.86), (0.64, 0.86)])
}

func drawGlyph(_ g: Glyph, _ c: Canvas, color: NSColor) {
    color.setStroke()
    color.setFill()
    switch g {
    case .mic:
        micBody(c)
    case .mail:
        let r = c.rect(0.10, 0.24, 0.80, 0.54)
        stroke(NSBezierPath(roundedRect: r, xRadius: c.r(0.07), yRadius: c.r(0.07)), c)
        line(c, [(0.14, 0.30), (0.50, 0.55), (0.86, 0.30)])
    case .voiceNote:
        // A small microphone next to note lines: speech into a note.
        let small = Canvas(box: CGRect(x: c.box.minX - c.r(0.20), y: c.box.minY + c.r(0.05), width: c.r(0.80), height: c.r(0.80)))
        micBody(small)
        line(c, [(0.62, 0.30), (0.92, 0.30)])
        line(c, [(0.62, 0.50), (0.92, 0.50)])
        line(c, [(0.62, 0.70), (0.84, 0.70)])
    case .wand:
        line(c, [(0.18, 0.84), (0.62, 0.40)], width: 0.10)
        star(c, x: 0.72, y: 0.26, size: 0.20)
        star(c, x: 0.36, y: 0.24, size: 0.11)
        star(c, x: 0.82, y: 0.62, size: 0.10)
    case .popup:
        stroke(NSBezierPath(roundedRect: c.rect(0.10, 0.16, 0.80, 0.68), xRadius: c.r(0.10), yRadius: c.r(0.10)), c)
        line(c, [(0.24, 0.36), (0.58, 0.36)], width: 0.065)
        line(c, [(0.24, 0.52), (0.76, 0.52)], width: 0.065)
        line(c, [(0.24, 0.68), (0.50, 0.68)], width: 0.065)
        star(c, x: 0.74, y: 0.32, size: 0.12)
    case .translate:
        stroke(NSBezierPath(roundedRect: c.rect(0.06, 0.10, 0.50, 0.50), xRadius: c.r(0.08), yRadius: c.r(0.08)), c, width: 0.06)
        text("A", c, x: 0.31, y: 0.35, size: 0.34, color: color)
        NSBezierPath(roundedRect: c.rect(0.44, 0.40, 0.50, 0.50), xRadius: c.r(0.08), yRadius: c.r(0.08)).fill()
        text("文", c, x: 0.69, y: 0.65, size: 0.30, color: NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1))
    case .emoji:
        stroke(NSBezierPath(ovalIn: c.rect(0.12, 0.12, 0.76, 0.76)), c)
        NSBezierPath(ovalIn: c.rect(0.33, 0.34, 0.09, 0.11)).fill()
        NSBezierPath(ovalIn: c.rect(0.58, 0.34, 0.09, 0.11)).fill()
        let smile = NSBezierPath()
        smile.appendArc(withCenter: c.p(0.50, 0.50), radius: c.r(0.22), startAngle: 205, endAngle: 335, clockwise: false)
        stroke(smile, c, width: 0.065)
    case .notes:
        stroke(NSBezierPath(roundedRect: c.rect(0.18, 0.08, 0.64, 0.84), xRadius: c.r(0.08), yRadius: c.r(0.08)), c)
        for y in [0.32, 0.50, 0.68] as [CGFloat] { line(c, [(0.32, y), (y == 0.68 ? 0.54 : 0.68, y)], width: 0.06) }
    case .quickNote:
        let b = NSBezierPath()
        b.move(to: c.p(0.14, 0.14)); b.line(to: c.p(0.86, 0.14)); b.line(to: c.p(0.86, 0.60))
        b.line(to: c.p(0.60, 0.86)); b.line(to: c.p(0.14, 0.86)); b.close()
        stroke(b, c)
        line(c, [(0.60, 0.86), (0.60, 0.60), (0.86, 0.60)], width: 0.06)
        line(c, [(0.28, 0.36), (0.66, 0.36)], width: 0.06)
        line(c, [(0.28, 0.52), (0.50, 0.52)], width: 0.06)
    case .screenText:
        let k: CGFloat = 0.20
        for (x, y, dx, dy) in [(0.10, 0.10, 1.0, 1.0), (0.90, 0.10, -1.0, 1.0), (0.10, 0.90, 1.0, -1.0), (0.90, 0.90, -1.0, -1.0)]
            as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            line(c, [(x, y + dy * k), (x, y), (x + dx * k, y)])
        }
        text("T", c, x: 0.50, y: 0.50, size: 0.46, color: color)
    case .password:
        stroke(NSBezierPath(ovalIn: c.rect(0.10, 0.30, 0.36, 0.36)), c)
        line(c, [(0.46, 0.48), (0.90, 0.48)])
        line(c, [(0.76, 0.48), (0.76, 0.64)])
        line(c, [(0.88, 0.48), (0.88, 0.60)])
    case .pause:
        for x in [0.28, 0.58] as [CGFloat] {
            NSBezierPath(roundedRect: c.rect(x, 0.20, 0.14, 0.60), xRadius: c.r(0.04), yRadius: c.r(0.04)).fill()
        }
    case .resume:
        let t = NSBezierPath()
        t.move(to: c.p(0.30, 0.18)); t.line(to: c.p(0.82, 0.50)); t.line(to: c.p(0.30, 0.82)); t.close()
        t.fill(); stroke(t, c, width: 0.06)
    case .autocomplete:
        // Text, then the suggestion and ⇥.
        line(c, [(0.10, 0.34), (0.40, 0.34)], width: 0.07)
        line(c, [(0.10, 0.52), (0.30, 0.52)], width: 0.07)
        line(c, [(0.10, 0.70), (0.36, 0.70)], width: 0.07)
        line(c, [(0.50, 0.52), (0.82, 0.52)])
        line(c, [(0.70, 0.40), (0.82, 0.52), (0.70, 0.64)])
        line(c, [(0.90, 0.36), (0.90, 0.68)])
    case .language:
        stroke(NSBezierPath(ovalIn: c.rect(0.12, 0.12, 0.76, 0.76)), c, width: 0.065)
        stroke(NSBezierPath(ovalIn: c.rect(0.33, 0.12, 0.34, 0.76)), c, width: 0.055)
        line(c, [(0.14, 0.50), (0.86, 0.50)], width: 0.055)
        line(c, [(0.22, 0.30), (0.78, 0.30)], width: 0.05)
        line(c, [(0.22, 0.70), (0.78, 0.70)], width: 0.05)
    case .toggle:
        stroke(NSBezierPath(roundedRect: c.rect(0.08, 0.28, 0.84, 0.44), xRadius: c.r(0.22), yRadius: c.r(0.22)), c)
        NSBezierPath(ovalIn: c.rect(0.52, 0.34, 0.32, 0.32)).fill()
    }
}

/// Four-pointed spark.
func star(_ c: Canvas, x: CGFloat, y: CGFloat, size s: CGFloat) {
    let b = NSBezierPath()
    let k = s * 0.22
    b.move(to: c.p(x, y - s)); b.line(to: c.p(x + k, y - k)); b.line(to: c.p(x + s, y)); b.line(to: c.p(x + k, y + k))
    b.line(to: c.p(x, y + s)); b.line(to: c.p(x - k, y + k)); b.line(to: c.p(x - s, y)); b.line(to: c.p(x - k, y - k)); b.close()
    b.fill()
}

enum Badge { case none, rec, busy }

/// `tile`: dark area with gradient. `scale`: share of the width for the glyph, `top`: distance from the top (share).
func render(_ g: Glyph, size: Int, color: NSColor, tile: Bool, scale: CGFloat, top: CGFloat, badge: Badge) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    if tile {
        NSGradient(starting: NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1),
                   ending: NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    }
    let gs = s * scale
    let c = Canvas(box: CGRect(x: (s - gs) / 2, y: s - s * top - gs, width: gs, height: gs))
    drawGlyph(g, c, color: color)
    switch badge {
    case .none: break
    case .rec:
        red.setFill()
        NSBezierPath(ovalIn: NSRect(x: s * 0.76, y: s * 0.06, width: s * 0.14, height: s * 0.14)).fill()
    case .busy:
        accent.setFill()
        for i in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: s * (0.60 + CGFloat(i) * 0.11), y: s * 0.07, width: s * 0.08, height: s * 0.08)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ name: String, _ g: Glyph, base: Int, color: NSColor, tile: Bool = true, scale: CGFloat = 0.48, top: CGFloat = 0.42,
           badge: Badge = .none) {
    for (suffix, factor) in [("", 1), ("@2x", 2)] {
        try! render(g, size: base * factor, color: color, tile: tile, scale: scale, top: top, badge: badge)
            .write(to: out.appendingPathComponent("\(name)\(suffix).png"))
    }
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Plugin icon (Stream Deck store/settings): accent on the tile.
write("plugin", .wand, base: 256, color: accent, scale: 0.60, top: 0.20)
// Action list in Stream Deck: plain white, no tile (Elgato style).
write("category", .wand, base: 28, color: white, tile: false, scale: 0.9, top: 0.05)
write("dictation", .mic, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
write("prompt", .wand, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
write("tool", .popup, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
write("toggle", .toggle, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
// Dials (shown round): glyph centred.
write("dictation-dial", .mic, base: 72, color: ink, scale: 0.56, top: 0.22)
write("prompt-dial", .wand, base: 72, color: ink, scale: 0.56, top: 0.22)
// Keys: glyph below, room for the title on top. One image per state.
for (name, g) in [("key-mic", Glyph.mic), ("key-mail", .mail), ("key-voicenote", .voiceNote)] {
    write(name, g, base: 72, color: ink)
    write(name + "-rec", g, base: 72, color: red, badge: .rec)
    write(name + "-busy", g, base: 72, color: accent, badge: .busy)
    write(name + "-off", g, base: 72, color: inkDim)
}
write("key-prompt", .wand, base: 72, color: ink)
write("key-popup", .popup, base: 72, color: ink)
write("key-translate", .translate, base: 72, color: ink)
write("key-emoji", .emoji, base: 72, color: ink)
write("key-notes", .notes, base: 72, color: ink)
write("key-quicknote", .quickNote, base: 72, color: ink)
write("key-screentext", .screenText, base: 72, color: ink)
write("key-password", .password, base: 72, color: ink)
write("key-pause", .pause, base: 72, color: ink, scale: 0.44)
write("key-resume", .resume, base: 72, color: accent, scale: 0.44)
write("key-autocomplete", .autocomplete, base: 72, color: inkDim)
write("key-autocomplete-on", .autocomplete, base: 72, color: accent)
write("key-language", .language, base: 72, color: ink)
FileHandle.standardError.write("icons written to \(out.path)\n".data(using: .utf8)!)
