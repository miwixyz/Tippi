/// Lauftext für die Leiste des Stream Deck Plus (übernommen aus Gnotchi, dort am Gerät gemessen M7). Stream Deck schneidet zu
/// langen Text mit „…“ ab und scrollt nicht selbst. Zeichenweise verschoben wirkte es wackelig (Michael 17.11., Fall A: ganze
/// Buchstaben, schwankende Breite) – deshalb zeichnet das Plugin die Zeile als Bild und dieser Baustein verschiebt sie
/// **pixelweise**. Rein, getestet; Einheiten sind Pixel, Takte kommen vom Plugin.
struct Marquee: Equatable {

    /// Sichtbare Breite in Pixeln.
    let view: Int
    /// Pixel je Takt.
    let step: Int
    /// Takte Pause am Anfang jeder Runde.
    let holdTicks: Int
    /// Lücke zwischen Ende und neuem Anfang (Pixel).
    let gap: Int

    /// Was gerade läuft (Text); nur bei Änderung beginnt der Lauf von vorn.
    private(set) var key: String = ""
    /// Breite des gezeichneten Texts in Pixeln.
    private(set) var content = 0
    /// Linker Rand des sichtbaren Ausschnitts im Streifen (Text + Lücke + Text).
    private(set) var offset = 0
    private var hold = 0

    init(view: Int = 176, step: Int = 3, holdTicks: Int = 18, gap: Int = 40) {
        self.view = max(1, view)
        self.step = max(1, step)
        self.holdTicks = max(0, holdTicks)
        self.gap = max(0, gap)
    }

    var scrolls: Bool { content > view }
    /// Länge einer Runde: Text plus Lücke.
    var loop: Int { content + gap }

    /// Neuer Inhalt: nur bei geändertem `key` von vorn beginnen.
    mutating func set(key: String, contentWidth: Int) {
        guard key != self.key || contentWidth != content else { return }
        self.key = key
        content = max(0, contentWidth)
        offset = 0
        hold = holdTicks
    }

    /// Einen Takt weiter. Rückgabe: ob sich der Ausschnitt verschoben hat.
    @discardableResult
    mutating func tick() -> Bool {
        guard scrolls else { return false }
        if hold > 0 { hold -= 1; return false }
        offset += step
        if offset >= loop { offset = 0; hold = holdTicks }
        return true
    }
}
