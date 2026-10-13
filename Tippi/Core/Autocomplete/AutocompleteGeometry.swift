import CoreGraphics

// MARK: - Platzierung

enum AutocompleteGeometry {
    /// Design §7: Wo Apps falsche Cursor-Bounds melden (Electron), lieber kein
    /// Vorschlag als ein falsch platzierter. Verworfen werden Rechtecke ohne
    /// Höhe, absurd große, der typische Nullpunkt-Müll und alles außerhalb
    /// der Bildschirme.
    static func isPlausibleCaret(_ rect: CGRect, screens: [CGRect]) -> Bool {
        guard rect.height >= 6, rect.height <= 200, rect.width >= 0, rect.width <= 400 else { return false }
        guard rect.origin != .zero else { return false }
        let probe = CGPoint(x: rect.midX, y: rect.midY)
        return screens.contains { $0.contains(probe) }
    }

    /// Ein Textmarker-Rechteck ist nur dann ein Cursor, wenn es (fast) keine Breite
    /// hat. Gemessen 2026-09-28 in Obsidian: Cursor in einer Notiz = Breite 0; leeres
    /// Eingabefeld = ganze Zeile (887 pt) — das darf nicht als Cursorstelle gelten.
    static func isCollapsedCaret(_ rect: CGRect) -> Bool {
        rect.width <= 2
    }

    /// Cursor (Breite 0) aus den beiden Rechtecken, die eine App liefern kann —
    /// beide schon auf Plausibilität geprüft, `nil` wenn keins.
    ///
    /// TextEdit (NSTextView) meldet den Cursor bei Länge 0 eine Zeilenhöhe zu
    /// hoch — gemessen 2026-10-13: Cursor y 430, Zeichen davor y 444, Höhe 14;
    /// der Vorschlag schwebte über der Zeile. Steht das Zeichen davor waagrecht
    /// direkt am Cursor, liegt es auf derselben Zeile — dann gilt seine Höhe.
    /// Sonst (Zeilenumbruch davor) bleibt das Cursor-Rechteck.
    static func caret(zeroLength: CGRect?, charBefore: CGRect?) -> CGRect? {
        if let zero = zeroLength {
            if let char = charBefore, abs(char.maxX - zero.minX) <= 2 {
                return CGRect(x: zero.minX, y: char.minY, width: 0, height: char.height)
            }
            return CGRect(x: zero.minX, y: zero.minY, width: 0, height: zero.height)
        }
        if let char = charBefore {
            return CGRect(x: char.maxX, y: char.minY, width: 0, height: char.height)
        }
        return nil
    }

    /// Schriftgröße passend zur Zeilenhöhe des Feldes, im Rahmen des Lesbaren.
    static func fontSize(forCaretHeight height: CGFloat) -> CGFloat {
        min(max(height * 0.8, 11), 28)
    }

    /// Schriftgröße für den Vorschlag: die von der App gemeldete Schriftgröße
    /// des Zeichens vor dem Cursor, wenn es eine gibt und sie zur Zeilenhöhe am
    /// Bildschirm passt — sonst die Schätzung aus der Zeilenhöhe. Bei Zoom
    /// (Pages auf 200 %) meldet die App Dokument-Punkte, nicht Bildschirm-Punkte;
    /// dann passt die Zahl nicht zur Cursorhöhe und wird verworfen.
    static func fontSize(reported: CGFloat?, caretHeight: CGFloat) -> CGFloat {
        guard let reported, reported >= caretHeight * 0.5, reported <= caretHeight else {
            return fontSize(forCaretHeight: caretHeight)
        }
        return min(max(reported, 11), 28)
    }
}
