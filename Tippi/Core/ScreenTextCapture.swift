import AppKit
import ScreenCaptureKit
import Vision
import os

private let ocrLog = Logger(subsystem: "com.tippi.app", category: "screen-ocr")

/// Erfasst einen Bildschirmausschnitt und liest den Text darin.
///
/// **Sicherheitsrahmen** — Begründung in `docs/SECURE-DESIGN-screen-ocr.md`:
///
/// Ein Bildschirmausschnitt hat keine feste Datenklasse. Er hat die höchste,
/// die gerade auf dem Schirm steht — ein sichtbares Passwort, ein Schlüssel im
/// Terminal, eine Patientenzeile. Die App kann das nicht unterscheiden und darf
/// es nicht versuchen. Deshalb gilt hier durchgehend:
///
/// - **Nie auf die Platte.** Das Bild lebt ausschließlich im Arbeitsspeicher.
///   Deshalb ScreenCaptureKit statt `screencapture -i`: Letzteres schreibt eine
///   PNG-Datei, die bei einem Absturz zwischen Aufnahme und Löschen liegen bleibt.
/// - **Nie in ein Protokoll.** Weder erkannter Text noch Ausschnitte davon,
///   auch nicht in Fehlermeldungen. Geloggt werden nur Vorgang, Zeichenzahl und
///   Fehlerkategorie.
/// - **Kein Verlauf.** Nichts wird zwischengespeichert.
/// - **Nur auf ausdrückliche Auslösung.** Kein Timer, kein Hintergrundlauf.
@MainActor
enum ScreenTextCapture {

    enum Failure: Error {
        case noPermission
        case blankCapture
        case displayUnavailable
        case captureFailed
        case recognitionFailed
        case empty

        var userMessage: String {
            switch self {
            case .noPermission:
                return "Tippi darf den Bildschirm nicht lesen.\n\n"
                     + "→ ZU TUN: Systemeinstellungen → Datenschutz & Sicherheit → "
                     + "Bildschirmaufnahme → Tippi aktivieren, danach Tippi neu starten."
            case .blankCapture:
                return "Der Ausschnitt kam leer zurück.\n\n"
                     + "Das heißt fast immer: Die Berechtigung Bildschirmaufnahme fehlt "
                     + "oder ist nach dem Erteilen noch nicht wirksam.\n\n"
                     + "→ ZU TUN: Systemeinstellungen → Datenschutz & Sicherheit → "
                     + "Bildschirmaufnahme → Tippi aktivieren, dann Tippi BEENDEN und neu "
                     + "starten. Ohne Neustart bleibt die Aufnahme schwarz."
            case .displayUnavailable:
                return "Der Bildschirm konnte nicht ermittelt werden. Bitte erneut versuchen."
            case .captureFailed:
                return "Der Ausschnitt konnte nicht aufgenommen werden. Bitte erneut versuchen."
            case .recognitionFailed:
                return "Die Texterkennung ist fehlgeschlagen. Bitte erneut versuchen."
            case .empty:
                return "In diesem Ausschnitt wurde kein Text gefunden."
            }
        }
    }

    /// Obergrenze der Pixelfläche. Darüber wird herunterskaliert statt
    /// abgelehnt — OCR braucht Kantenschärfe, keine Auflösungsrekorde, und eine
    /// Auswahl über vier 5K-Schirme würde sonst Sekunden und viel Speicher kosten.
    private static let maxPixels: Int = 12_000_000

    /// Fest auf Deutsch und Englisch. Jede weitere Sprache senkt die Trefferquote
    /// der anderen, weil Vision mehr raten muss (entschieden 2026-09-21).
    private static let languages = ["de-DE", "en-US"]

    // MARK: - Eingefrorener Bildschirm (freeze-first)

    /// Ein eingefrorener Bildschirm: Bild plus die Geometrie, die zum
    /// Zurückrechnen nötig ist.
    struct FrozenScreen {
        /// AppKit-Bildschirmkoordinaten in Punkten, Ursprung unten links.
        let frame: CGRect
        /// Pixel, Ursprung **oben links**.
        let image: CGImage
    }

    /// Nimmt **alle** Bildschirme auf, bevor irgendeine Oberfläche erscheint.
    ///
    /// **Warum diese Reihenfolge (Befund von Michael, 2026-09-22):** Das
    /// Auswahl-Overlay ruft `NSApp.activate(ignoringOtherApps:)` — und das
    /// schließt jedes Pop-Up, Menü und Tooltip. Wer Text aus einem Pop-Up
    /// erfassen wollte, bekam einen Bildschirm ohne das Pop-Up. Die Auswahl kam
    /// zu spät.
    ///
    /// Jetzt wird zuerst eingefroren und dann auf dem **Standbild** ausgewählt.
    /// Das Pop-Up ist im Bild, egal ob es real noch offen ist. Nebeneffekt: Man
    /// sieht genau, was aufgenommen wurde — und eine fehlende Berechtigung
    /// fällt **vor** dem Aufziehen auf, nicht danach.
    static func freezeAllScreens() async throws -> [FrozenScreen] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            ocrLog.error("Bildschirminhalt nicht verfügbar — vermutlich fehlende Berechtigung")
            throw Failure.noPermission
        }

        var result: [FrozenScreen] = []
        for display in content.displays {
            // Zuordnung über die Display-ID, nicht über die Geometrie: Zwei
            // Bildschirme können dieselbe Größe haben.
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                    == display.displayID
            }) else { continue }

            let scale = screen.backingScaleFactor
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.captureResolution = .best
            config.showsCursor = false
            config.width = max(1, Int(screen.frame.width * scale))
            config.height = max(1, Int(screen.frame.height * scale))

            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )
                result.append(FrozenScreen(frame: screen.frame, image: image))
            } catch {
                ocrLog.error("Aufnahme eines Bildschirms fehlgeschlagen")
                throw Failure.captureFailed
            }
        }

        guard !result.isEmpty else { throw Failure.displayUnavailable }
        // Nur Geometrie, kein Inhalt.
        ocrLog.info("\(result.count) Bildschirm(e) eingefroren")
        return result
    }

    /// **Reine** Umrechnung: Auswahl (AppKit global, Punkte, Y nach oben) →
    /// Zuschnitt im eingefrorenen Bild (Pixel, Ursprung oben links).
    ///
    /// Ausgelagert und ohne Seiteneffekte, weil genau hier schon einmal ein
    /// Fehler saß: Die erste Fassung des Bildschirm-OCR erfasste einen vertikal
    /// **gespiegelten** Bereich — wer oben auswählte, bekam unten. Das fiel
    /// nicht als Fehler auf, sondern als „kein Text gefunden". Jetzt prüfbar
    /// ohne Bildschirm, ohne Berechtigung und ohne Aufnahme.
    nonisolated static func cropRect(selection: CGRect, screenFrame: CGRect,
                         imagePixelSize: CGSize) -> CGRect {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return .zero }
        let sx = imagePixelSize.width / screenFrame.width
        let sy = imagePixelSize.height / screenFrame.height

        // Y umdrehen: AppKit zählt von unten, CoreGraphics-Bilder von oben.
        let localX = selection.minX - screenFrame.minX
        let localTop = screenFrame.maxY - selection.maxY

        return CGRect(x: (localX * sx).rounded(.down),
                      y: (localTop * sy).rounded(.down),
                      width: max(1, (selection.width * sx).rounded()),
                      height: max(1, (selection.height * sy).rounded()))
    }

    /// Welcher eingefrorene Bildschirm enthält die Auswahl?
    nonisolated static func screen(for selection: CGRect,
                       in frozen: [FrozenScreen]) -> FrozenScreen? {
        frozen.first { $0.frame.intersects(selection) } ?? frozen.first
    }

    /// OCR auf dem Zuschnitt eines **eingefrorenen** Bildes.
    static func text(in rect: CGRect, from frozen: [FrozenScreen]) async throws -> String {
        guard rect.width >= 4, rect.height >= 4 else { throw Failure.empty }
        guard let target = screen(for: rect, in: frozen) else {
            throw Failure.displayUnavailable
        }

        let pixelSize = CGSize(width: target.image.width, height: target.image.height)
        let crop = cropRect(selection: rect, screenFrame: target.frame,
                            imagePixelSize: pixelSize)
        ocrLog.info("Zuschnitt \(Int(crop.minX)),\(Int(crop.minY)) \(Int(crop.width))x\(Int(crop.height)) aus \(Int(pixelSize.width))x\(Int(pixelSize.height))")

        guard let cropped = target.image.cropping(to: crop) else {
            ocrLog.error("Zuschnitt lag außerhalb des Bildes")
            throw Failure.captureFailed
        }

        if isBlank(cropped) {
            ocrLog.error("Aufnahme einfarbig — Berechtigung fehlt vermutlich")
            throw Failure.blankCapture
        }

        let image = downscaleIfNeeded(cropped)
        return try await recognize(image)
    }

    /// Verkleinert, wenn der Zuschnitt die Pixelgrenze überschreitet. OCR
    /// braucht Kantenschärfe, keine Auflösungsrekorde.
    private static func downscaleIfNeeded(_ image: CGImage) -> CGImage {
        let pixels = image.width * image.height
        guard pixels > maxPixels else { return image }
        let factor = (Double(maxPixels) / Double(pixels)).squareRoot()
        let w = max(1, Int(Double(image.width) * factor))
        let h = max(1, Int(Double(image.height) * factor))
        ocrLog.info("Zuschnitt herunterskaliert auf \(w)×\(h)")
        guard let space = image.colorSpace,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Erfasst `rect` (in globalen Bildschirmkoordinaten) und gibt den Text zurück.
    ///
    /// **Älterer Weg**, nimmt erst nach der Auswahl auf. Bleibt für Aufrufer
    /// ohne eingefrorenes Bild; der Bildschirm-OCR benutzt ihn seit 2026-09-22
    /// nicht mehr.
    static func text(in rect: CGRect) async throws -> String {
        guard rect.width >= 4, rect.height >= 4 else { throw Failure.empty }

        let image = try await capture(rect)
        // ScreenCaptureKit meldet fehlende Berechtigung NICHT als Fehler — es
        // liefert ein schwarzes Bild. Ohne diese Pruefung sieht das exakt aus
        // wie "der Ausschnitt enthielt keinen Text", und man sucht am falschen
        // Ende. Befund aus dem ersten Praxistest, 2026-09-21.
        if isBlank(image) {
            ocrLog.error("Aufnahme einfarbig — Berechtigung fehlt vermutlich")
            throw Failure.blankCapture
        }
        defer {
            // Hinweis für den Leser: `image` ist hier gleich nicht mehr
            // erreichbar. Der enge Gültigkeitsbereich ist Absicht — der Puffer
            // soll so kurz wie möglich im Adressraum liegen.
            ocrLog.debug("Ausschnitt verarbeitet, Puffer freigegeben")
        }
        return try await recognize(image)
    }

    // MARK: - Aufnahme

    private static func capture(_ rect: CGRect) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            // SCShareableContent schlägt genau dann fehl, wenn die Berechtigung
            // fehlt. Die Fehlermeldung selbst ist wenig aussagekräftig, deshalb
            // wird sie hier in eine Handlungsanweisung übersetzt.
            ocrLog.error("Bildschirminhalt nicht verfügbar — vermutlich fehlende Berechtigung")
            throw Failure.noPermission
        }

        // Der Bildschirm, auf dem die Auswahl liegt.
        guard let display = content.displays.first(where: {
            CGRect(x: $0.frame.minX, y: $0.frame.minY,
                   width: $0.frame.width, height: $0.frame.height).intersects(rect)
        }) ?? content.displays.first else {
            throw Failure.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // ── Koordinatenwechsel, der die erste Fassung unbrauchbar machte ──
        //
        // `rect` kommt aus AppKit (NSWindow.convertToScreen): Ursprung unten
        // links, Y waechst nach oben. `sourceRect` erwartet CoreGraphics:
        // Ursprung oben links, Y waechst nach unten.
        //
        // Ohne Umrechnung wird ein vertikal gespiegelter Bereich erfasst — wer
        // oben auswaehlt, bekommt unten. Das faellt nicht als Fehler auf,
        // sondern als "kein Text gefunden", weil dort meist nichts steht.
        let displayW = CGFloat(display.width)
        let displayH = CGFloat(display.height)
        let local = CGRect(
            x: rect.minX - display.frame.minX,
            y: displayH - (rect.maxY - display.frame.minY),
            width: rect.width,
            height: rect.height
        )
        // Nur Geometrie, kein Inhalt — der Messpunkt, der beim ersten
        // Fehlschlag fehlte.
        ocrLog.info("Ausschnitt lokal \(Int(local.minX)),\(Int(local.minY)) \(Int(local.width))x\(Int(local.height)) auf Display \(Int(displayW))x\(Int(displayH))")
        config.sourceRect = local
        config.captureResolution = .best
        config.showsCursor = false

        // Skalierung gegen übergroße Auswahlen.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var pixelW = Int(local.width * scale)
        var pixelH = Int(local.height * scale)
        if pixelW * pixelH > maxPixels {
            let factor = (Double(maxPixels) / Double(pixelW * pixelH)).squareRoot()
            pixelW = Int(Double(pixelW) * factor)
            pixelH = Int(Double(pixelH) * factor)
            ocrLog.info("Auswahl herunterskaliert auf \(pixelW)×\(pixelH)")
        }
        config.width = max(1, pixelW)
        config.height = max(1, pixelH)

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        } catch {
            ocrLog.error("Aufnahme fehlgeschlagen")
            throw Failure.captureFailed
        }
    }

    /// Ist das Bild praktisch einfarbig? Dann kam nichts an.
    ///
    /// Betrachtet werden Stichproben der Rohbytes, nur auf Streuung — es geht um
    /// "schwarz oder nicht", nicht um Bildanalyse. Inhalte werden weder
    /// ausgewertet noch protokolliert.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let length = CFDataGetLength(data)
        guard length > 0 else { return true }

        let step = max(1, length / 2000)
        var minV: UInt8 = 255
        var maxV: UInt8 = 0
        var i = 0
        while i < length {
            let v = ptr[i]
            if v < minV { minV = v }
            if v > maxV { maxV = v }
            if Int(maxV) - Int(minV) > 12 { return false }
            i += step
        }
        return true
    }

    // MARK: - Texterkennung

    private static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    // Bewusst ohne `error` im Log: Vision hängt in manchen
                    // Fehlerfällen erkannte Fragmente an die Meldung an.
                    ocrLog.error("Texterkennung fehlgeschlagen")
                    continuation.resume(throwing: Failure.recognitionFailed)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                let text = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    continuation.resume(throwing: Failure.empty)
                } else {
                    // Nur die Länge, nie der Inhalt.
                    ocrLog.info("Text erkannt: \(text.count, privacy: .public) Zeichen")
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                ocrLog.error("Texterkennung konnte nicht starten")
                continuation.resume(throwing: Failure.recognitionFailed)
            }
        }
    }

    // MARK: - Zwischenablage

    /// Legt den Text in die Zwischenablage.
    ///
    /// `prepareForNewContents(with: .currentHostOnly)` ist der entscheidende
    /// Teil: Ohne ihn synchronisiert macOS die Zwischenablage über Handoff auf
    /// iPhone und iPad. Ein per OCR erfasstes Passwort verließe damit das Gerät
    /// — obwohl an diesem Feature keine Zeile Netzwerkcode steht. Bewusst ohne
    /// Schalter: Eine Einstellung, die das aufhebt, macht die Zusage
    /// „bleibt auf dem Gerät" unzuverlässig.
    static func copyToPasteboard(_ text: String, concealed: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)

        if concealed {
            // Konvention, an die sich Raycast, Alfred, Paste und andere halten:
            // Inhalte mit diesem Typ werden nicht in den Verlauf übernommen.
            pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        }
        pasteboard.setString(text, forType: .string)
    }
}
