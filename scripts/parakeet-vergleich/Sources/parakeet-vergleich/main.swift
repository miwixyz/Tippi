import AVFoundation
import FluidAudio
import Foundation
import Wortfehler

// Parakeet v3 gegen Parakeet Ultra an eigenen Aufnahmen (2026-10-27).
//
// Ordner mit Paaren `name.wav` + `name.txt` (Referenztext, so geschrieben, wie
// der Text am Ende dastehen soll). Jede Datei wird mit jedem Modell genau so
// transkribiert wie in Tippi (`ParakeetTranscriber.transcribe(wavURL:)`:
// AsrManager mit Standardkonfiguration, frischer Decoder-Zustand je Datei,
// Sprachhinweis). Ausgabe: Wortfehlerrate je Datei und gesamt, Rechenzeit.
//
// Modelle liegen im selben Ordner wie bei Tippi
// (~/Library/Application Support/FluidAudio/Models/…). Fehlt eins, bricht das
// Programm ab und nennt die Größe — geladen wird nur mit `--laden`.

struct Optionen {
    var ordner: URL
    var modelle: [AsrModelVersion] = [.v3, .ultra]
    var sprache: Language? = .german
    var laden = false
    var texte = false
}

func hilfe() -> Never {
    print("""
    Aufruf: parakeet-vergleich <ordner> [--modelle v3,ultra] [--sprache de|en|…|auto] [--laden] [--texte]

      <ordner>    Paare name.wav + name.txt (Referenztext)
      --modelle   Welche Modelle, Standard: v3,ultra
      --sprache   Sprachhinweis wie in Tippi, Standard: de; auto = ohne Hinweis
      --laden     Fehlende Modelle herunterladen (v3 ≈ 470 MB, Ultra ≈ 630 MB)
      --texte     Erkannten Text je Datei mit ausgeben
    """)
    exit(2)
}

func leseOptionen() -> Optionen {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let erstes = args.first, !erstes.hasPrefix("-") else { hilfe() }
    args.removeFirst()
    var opt = Optionen(ordner: URL(fileURLWithPath: erstes, isDirectory: true))
    while let a = args.first {
        args.removeFirst()
        switch a {
        case "--modelle":
            guard let wert = args.first else { hilfe() }
            args.removeFirst()
            opt.modelle = wert.split(separator: ",").map { name -> AsrModelVersion in
                switch name {
                case "v3": return .v3
                case "ultra": return .ultra
                default:
                    print("Unbekanntes Modell: \(name) (erlaubt: v3, ultra)")
                    exit(2)
                }
            }
        case "--sprache":
            guard let wert = args.first else { hilfe() }
            args.removeFirst()
            if wert == "auto" {
                opt.sprache = nil
            } else if let sprache = Language(rawValue: wert) {
                opt.sprache = sprache
            } else {
                print("Unbekannte Sprache: \(wert)")
                exit(2)
            }
        case "--laden": opt.laden = true
        case "--texte": opt.texte = true
        default: hilfe()
        }
    }
    return opt
}

func name(_ version: AsrModelVersion) -> String {
    version == .ultra ? "Ultra" : "v3"
}

struct Paar {
    let name: String
    let wav: URL
    let referenz: String
    let sekunden: Double
}

func lesePaare(in ordner: URL) throws -> [Paar] {
    let dateien = try FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)
    return try dateien
        .filter { $0.pathExtension.lowercased() == "wav" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { wav -> Paar? in
            let txt = wav.deletingPathExtension().appendingPathExtension("txt")
            guard FileManager.default.fileExists(atPath: txt.path) else {
                print("⚠︎ \(wav.lastPathComponent): keine passende .txt — übersprungen")
                return nil
            }
            let datei = try AVAudioFile(forReading: wav)
            let sekunden = Double(datei.length) / datei.fileFormat.sampleRate
            return Paar(name: wav.deletingPathExtension().lastPathComponent, wav: wav,
                        referenz: try String(contentsOf: txt, encoding: .utf8), sekunden: sekunden)
        }
}

struct Messung {
    var ergebnis: Wortfehler.Ergebnis
    var rechenzeit: Double
    var text: String
}

func messe(_ version: AsrModelVersion, paare: [Paar], opt: Optionen) async throws -> (laden: Double, je: [Messung]) {
    let ordner = AsrModels.defaultCacheDirectory(for: version)
    if !AsrModels.modelsExist(at: ordner, version: version) {
        guard opt.laden else {
            print("✗ Parakeet \(name(version)) ist nicht geladen (\(ordner.path)).")
            print("  → ZU TUN: mit --laden erneut starten (lädt v3 ≈ 470 MB bzw. Ultra ≈ 630 MB von Hugging Face)")
            exit(1)
        }
        print("… lade Parakeet \(name(version)) herunter")
    }
    let start = Date()
    let modelle = try await AsrModels.downloadAndLoad(version: version)
    let manager = AsrManager()
    try await manager.loadModels(modelle)
    let laden = Date().timeIntervalSince(start)

    // Aufwärmen: der erste Durchlauf auf der Neural Engine ist langsamer. Gilt
    // für beide Modelle gleich und gehört nicht in die Rechenzeit je Datei.
    if let erstes = paare.first {
        var zustand = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        _ = try? await manager.transcribe(erstes.wav, decoderState: &zustand, language: opt.sprache)
    }

    var je: [Messung] = []
    for paar in paare {
        var zustand = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let t0 = Date()
        let ergebnis = try await manager.transcribe(paar.wav, decoderState: &zustand, language: opt.sprache)
        let dauer = Date().timeIntervalSince(t0)
        let text = ergebnis.text.trimmingCharacters(in: .whitespacesAndNewlines)
        je.append(Messung(ergebnis: Wortfehler.vergleiche(referenz: paar.referenz, erkannt: text),
                          rechenzeit: dauer, text: text))
    }
    return (laden, je)
}

func prozent(_ wert: Double) -> String { String(format: "%5.1f %%", wert * 100) }
func sek(_ wert: Double) -> String { String(format: "%5.2f s", wert) }
func spalte(_ text: String, _ breite: Int) -> String {
    text.count >= breite ? String(text.prefix(breite)) : text + String(repeating: " ", count: breite - text.count)
}

let opt = leseOptionen()
let paare: [Paar]
do {
    paare = try lesePaare(in: opt.ordner)
} catch {
    print("✗ Ordner nicht lesbar: \(error.localizedDescription)")
    exit(1)
}
guard !paare.isEmpty else {
    print("✗ Keine Paare name.wav + name.txt in \(opt.ordner.path)")
    exit(1)
}

// Erst prüfen, ob alles da ist — sonst rechnet v3 eine Minute und erst dann
// fällt auf, dass Ultra fehlt.
let fehlend = opt.modelle.filter { !AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: $0), version: $0) }
if !fehlend.isEmpty, !opt.laden {
    print("✗ Nicht geladen: \(fehlend.map { "Parakeet " + name($0) }.joined(separator: ", "))")
    print("  → ZU TUN: mit --laden erneut starten (lädt v3 ≈ 470 MB bzw. Ultra ≈ 630 MB von Hugging Face)")
    exit(1)
}

var messungen: [(AsrModelVersion, Double, [Messung])] = []
for version in opt.modelle {
    do {
        let (laden, je) = try await messe(version, paare: paare, opt: opt)
        messungen.append((version, laden, je))
    } catch {
        print("✗ Parakeet \(name(version)): \(error.localizedDescription)")
        exit(1)
    }
}

let audioGesamt = paare.reduce(0) { $0 + $1.sekunden }
print("")
print("\(paare.count) Dateien, \(sek(audioGesamt)) Audio, Sprachhinweis: \(opt.sprache?.rawValue ?? "auto")")
var kopf = spalte("Datei", 24) + spalte("Audio", 9)
for (v, _, _) in messungen { kopf += spalte("WER \(name(v))", 12) + spalte("Zeit \(name(v))", 12) }
print(kopf)
for (i, paar) in paare.enumerated() {
    var zeile = spalte(paar.name, 24) + spalte(sek(paar.sekunden), 9)
    for (_, _, je) in messungen { zeile += spalte(prozent(je[i].ergebnis.rate), 12) + spalte(sek(je[i].rechenzeit), 12) }
    print(zeile)
    if opt.texte {
        print("    Referenz: \(paar.referenz.trimmingCharacters(in: .whitespacesAndNewlines))")
        for (v, _, je) in messungen { print("    \(spalte(name(v) + ":", 9)) \(je[i].text)") }
    }
}
print("")
for (v, laden, je) in messungen {
    let summe = je.reduce(Wortfehler.Ergebnis(fehler: 0, referenzWoerter: 0)) { $0 + $1.ergebnis }
    let zeit = je.reduce(0) { $0 + $1.rechenzeit }
    print("Gesamt \(spalte(name(v), 6)) WER \(prozent(summe.rate)) (\(summe.fehler) Fehler / \(summe.referenzWoerter) Wörter) · "
          + "Rechenzeit \(sek(zeit)) (\(String(format: "%.0f", audioGesamt / max(zeit, 0.001)))× Echtzeit) · Laden \(sek(laden))")
}
