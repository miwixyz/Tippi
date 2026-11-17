import AppKit

/// Zeichnet die Titelzeile der Leiste als Bild (Lauftext pixelweise, Michael 17.11.). Ein Streifen „Text · Lücke · Text“ wird
/// je Text einmal gezeichnet; jeder Takt schneidet nur den sichtbaren Ausschnitt heraus und kodiert ihn als PNG.
@MainActor
final class TrackImage {

    /// Größe des Bild-Felds im Layout (`layouts/dial.json`, Schlüssel `track`).
    static let size = (width: 176, height: 30)
    static let font = NSFont.systemFont(ofSize: 17, weight: .regular)
    static let color = NSColor(white: 0.96, alpha: 1)

    private var cacheKey = ""
    private var strip: CGImage?
    private(set) var contentWidth = 0

    /// Streifen für `text` vorbereiten (nur bei geändertem Text). Rückgabe: Breite des Texts in Pixeln.
    @discardableResult
    func prepare(_ text: String, gap: Int) -> Int {
        guard text != cacheKey || strip == nil else { return contentWidth }
        cacheKey = text
        let attr = NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: Self.color])
        let w = Int(ceil(attr.size().width))
        contentWidth = w
        let total = max(Self.size.width, w * 2 + gap)
        strip = Self.draw(attr, contentWidth: w, gap: gap, total: total)
        return w
    }

    private static func draw(_ attr: NSAttributedString, contentWidth: Int, gap: Int, total: Int) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: total, pixelsHigh: size.height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let y = (CGFloat(size.height) - attr.size().height) / 2
        attr.draw(at: NSPoint(x: 0, y: y))
        if contentWidth > size.width { attr.draw(at: NSPoint(x: CGFloat(contentWidth + gap), y: y)) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    /// Sichtbarer Ausschnitt ab `offset` als `data:`-URL für `setFeedback`.
    func frame(offset: Int) -> String? {
        guard let strip else { return nil }
        let x = min(max(0, offset), max(0, strip.width - Self.size.width))
        guard let cut = strip.cropping(to: CGRect(x: x, y: 0, width: Self.size.width, height: Self.size.height)) else { return nil }
        guard let png = NSBitmapImageRep(cgImage: cut).representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
