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
            case .noPermission:       return String(localized: "ocr.error.noPermission")
            case .blankCapture:       return String(localized: "ocr.error.blankCapture")
            case .displayUnavailable: return String(localized: "ocr.error.displayUnavailable")
            case .captureFailed:      return String(localized: "ocr.error.captureFailed")
            case .recognitionFailed:  return String(localized: "ocr.error.recognitionFailed")
            case .empty:              return String(localized: "ocr.error.empty")
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

    /// Welcher eingefrorene Bildschirm enthält die Auswahl? Der mit der größten
    /// Überdeckung — nicht der erste berührte: Eine Auswahl, die 1 pt in einen
    /// anderen Monitor ragte, wurde sonst dort als 1–2-px-Streifen ausgeschnitten
    /// (Audit 2026-09-27, Absturz in `recognize`).
    nonisolated static func screen(for selection: CGRect,
                                   in frozen: [FrozenScreen]) -> FrozenScreen? {
        let area: (FrozenScreen) -> CGFloat = { screen in
            let overlap = screen.frame.intersection(selection)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        return frozen.filter { area($0) > 0 }.max { area($0) < area($1) } ?? frozen.first
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
        // Vision lehnt Bilder mit ≤ 2 px Kantenlänge ab (gemessen 2026-09-27).
        guard cropped.width >= 3, cropped.height >= 3 else { throw Failure.empty }

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

    // MARK: - Aufnahme

    /// Ist das Bild praktisch einfarbig? Dann kam nichts an.
    ///
    /// Betrachtet werden Stichproben der Rohbytes, nur auf Streuung — es geht um
    /// "schwarz oder nicht", nicht um Bildanalyse. Inhalte werden weder
    /// ausgewertet noch protokolliert.
    /// Drawn into an 8-bit grey buffer with no interpolation (point samples,
    /// up to 256×256), then min/max. Sampling the raw bytes read the alpha
    /// channel as a colour, so an opaque black capture — the "no permission"
    /// case this exists for — was usually NOT detected (audit 2026-09-27,
    /// measured on BGRA).
    nonisolated static func isBlank(_ image: CGImage) -> Bool {
        let width = min(image.width, 256), height = min(image.height, 256)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = ctx.data else { return false }
        let pixels = UnsafeBufferPointer(start: raw.bindMemory(to: UInt8.self, capacity: width * height),
                                         count: width * height)
        guard let lo = pixels.min(), let hi = pixels.max() else { return true }
        // Uniform AND dark: a missing permission yields black. A uniform LIGHT
        // sample is usually a big selection with little text the point samples
        // missed — Vision decides that one (it says "no text" itself) instead
        // of a false "permission missing" (review 2026-09-27, measured).
        return Int(hi) - Int(lo) <= 12 && hi < 24
    }

    // MARK: - Texterkennung

    private static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // Vision meldet manche Fehler doppelt — per Completion-Handler UND
            // per `perform`-Exception (gemessen 2026-09-27). Ein zweites `resume`
            // ist ein Absturz; dieser Wächter lässt nur das erste durch.
            let once = ResumeOnce()
            let request = VNRecognizeTextRequest { request, error in
                guard once.claim() else { return }
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

            // Off the main thread: `.accurate` takes ~0.5–1 s on a large crop
            // (measured) and froze the menu bar and every panel meanwhile
            // (audit 2026-09-27). The continuation may resume from any thread.
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    guard once.claim() else { return }
                    ocrLog.error("Texterkennung konnte nicht starten")
                    continuation.resume(throwing: Failure.recognitionFailed)
                }
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

/// Lässt genau einen Aufrufer durch — für Continuations, die zwei mögliche
/// Fortsetzungswege haben.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
