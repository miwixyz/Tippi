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

    /// Erfasst `rect` (in globalen Bildschirmkoordinaten) und gibt den Text zurück.
    static func text(in rect: CGRect) async throws -> String {
        guard rect.width >= 4, rect.height >= 4 else { throw Failure.empty }

        let image = try await capture(rect)
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

        // sourceRect ist relativ zum Display, nicht global.
        let local = CGRect(x: rect.minX - CGFloat(display.frame.minX),
                           y: rect.minY - CGFloat(display.frame.minY),
                           width: rect.width, height: rect.height)
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
