import AVFoundation
import FluidAudio
import Foundation

// Spike 2026-10-02: Kann Tippi Live-Text mit dem VORHANDENEN Parakeet TDT v3 zeigen?
// Vergleicht SlidingWindowAsrManager (Live, Echtzeit-Einspeisung) mit Tippis Batch-Weg
// (AsrManager.transcribe wie ParakeetTranscriber.swift). Kein Eingriff in Tippi.

func normal(_ s: String) -> [String] {
    s.lowercased()
        .replacingOccurrences(of: "[^a-zäöüß0-9 ]", with: " ", options: .regularExpression)
        .split(separator: " ").map(String.init)
}

/// Wortfehlerrate (Levenshtein auf Wortebene) / Referenzlänge
func wer(_ ref: String, _ hyp: String) -> Double {
    let r = normal(ref), h = normal(hyp)
    var d = Array(0...h.count)
    for i in 1...max(r.count, 1) where !r.isEmpty {
        var prev = d[0]; d[0] = i
        for j in stride(from: 1, through: h.count, by: 1) {
            let tmp = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] == h[j - 1] ? 0 : 1))
            prev = tmp
        }
    }
    return r.isEmpty ? 0 : Double(d[h.count]) / Double(r.count)
}

func pct(_ x: Double) -> String { String(format: "%.1f %%", x * 100) }

@main
struct Spike {
    static func main() async throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "neu" {
            try await neuerkennung(dir: dir, models: models); return
        }

        let batch = AsrManager()
        try await batch.loadModels(models)

        for n in [1, 2] {
            let wav = dir.appendingPathComponent("t\(n).wav")
            let ref = try String(contentsOf: dir.appendingPathComponent("text\(n).txt"), encoding: .utf8)
            print("\n════ Aufnahme \(n)")

            // ── Batch wie Tippi heute (nach dem Loslassen)
            var st = TdtDecoderState.make()
            let tb = Date()
            let b = try await batch.transcribe(wav, decoderState: &st, language: Language(rawValue: "de"))
            let batchZeit = Date().timeIntervalSince(tb)
            print("BATCH  WER \(pct(wer(ref, b.text))) · \(String(format: "%.2f", batchZeit)) s nach Loslassen")
            print("       „\(b.text)“")

            // ── Live: Echtzeit-Einspeisung in 100-ms-Puffern
            for (name, cfg) in [
                ("streaming 11s", SlidingWindowAsrConfig.streaming),
                ("fenster 1,5s", SlidingWindowAsrConfig(chunkSeconds: 1.5, hypothesisChunkSeconds: 1.0, leftContextSeconds: 8.0, rightContextSeconds: 0.5, minContextForConfirmation: 10.0, confirmationThreshold: 0.8)),
                ("fenster 2s", SlidingWindowAsrConfig(chunkSeconds: 2.0, hypothesisChunkSeconds: 1.0, leftContextSeconds: 6.0, rightContextSeconds: 0.5, minContextForConfirmation: 10.0, confirmationThreshold: 0.8)),
                ("fenster 3s", SlidingWindowAsrConfig(chunkSeconds: 3.0, hypothesisChunkSeconds: 1.0, leftContextSeconds: 6.0, rightContextSeconds: 1.0, minContextForConfirmation: 10.0, confirmationThreshold: 0.8)),
            ] {
                let live = SlidingWindowAsrManager(config: cfg)
                try await live.loadModels(models)
                try await live.startStreaming(source: .microphone)
                let t0 = Date()
                var ersteZeit: Double? = nil
                var anzahl = 0
                var zeitpunkte: [Double] = []
                var letzteAnzeige = ""
                let sammler = Task {
                    for await _ in await live.transcriptionUpdates {
                        let anzeige = (await live.confirmedTranscript + " " + live.volatileTranscript)
                            .trimmingCharacters(in: .whitespaces)
                        if !anzeige.isEmpty && ersteZeit == nil { ersteZeit = Date().timeIntervalSince(t0) }
                        anzahl += 1
                        zeitpunkte.append(Date().timeIntervalSince(t0))
                        letzteAnzeige = anzeige
                    }
                }
                let file = try AVAudioFile(forReading: wav)
                let fmt = file.processingFormat
                let block: AVAudioFrameCount = AVAudioFrameCount(fmt.sampleRate / 10)
                while file.framePosition < file.length {
                    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: block)!
                    try file.read(into: buf, frameCount: block)
                    await live.streamAudio(buf)
                    try await Task.sleep(nanoseconds: 100_000_000)   // Echtzeit: wie gesprochen
                }
                let audioEnde = Date()
                let anzeigeBeimLoslassen = letzteAnzeige
                let final = try await live.finish()
                let nachLoslassen = Date().timeIntervalSince(audioEnde)
                sammler.cancel()
                let luecken = zip(zeitpunkte.dropFirst(), zeitpunkte).map { $0 - $1 }
                let takt = luecken.isEmpty ? 0 : luecken.reduce(0, +) / Double(luecken.count)
                print("LIVE[\(name)] Takt Ø \(String(format: "%.1f", takt)) s · erster Text nach \(ersteZeit.map { String(format: "%.1f s", $0) } ?? "–") · \(anzahl) Updates · Ende \(String(format: "%.2f", nachLoslassen)) s nach Loslassen")
                print("       WER Endtext \(pct(wer(ref, final))) · Umspringen beim Loslassen \(pct(wer(final, anzeigeBeimLoslassen)))")
                print("       Anzeige beim Loslassen: „\(anzeigeBeimLoslassen.suffix(160))“")
                print("       Endtext: „\(final)“")
            }
        }
    }
}


func samples(_ url: URL) throws -> [Float] {
    let f = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try f.read(into: buf)
    return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
}

/// Idee: waehrend der Aufnahme jede Sekunde ALLES bisher Gesagte mit dem Batch-Weg neu erkennen.
func neuerkennung(dir: URL, models: AsrModels) async throws {
    let mgr = AsrManager(); try await mgr.loadModels(models)
    let r1 = try String(contentsOf: dir.appendingPathComponent("text1.txt"), encoding: .utf8)
    let r2 = try String(contentsOf: dir.appendingPathComponent("text2.txt"), encoding: .utf8)
    let a1 = try samples(dir.appendingPathComponent("t1.wav")), a2 = try samples(dir.appendingPathComponent("t2.wav"))
    let pause = [Float](repeating: 0, count: 8000)
    let faelle: [(String, [Float], String)] = [
        ("Aufnahme 1 (29 s)", a1, r1),
        ("Aufnahme 2 (23 s)", a2, r2),
        ("lang (~110 s)", a1 + pause + a2 + pause + a1 + pause + a2, [r1, r2, r1, r2].joined(separator: " ")),
    ]
    for (name, audio, ref) in faelle {
        let dauer = Double(audio.count) / 16000
        let t0 = Date()
        var rechen: [Double] = []
        var ersteZeit: Double? = nil
        var letzteVorschau = ""
        while true {
            let jetzt = Date().timeIntervalSince(t0)
            if jetzt >= dauer { break }
            let n = min(audio.count, Int(jetzt * 16000))
            if n >= 16000 {   // ab 1 s Sprache
                var st = TdtDecoderState.make()
                let tr = Date()
                let r = try await mgr.transcribe(Array(audio[0..<n]), decoderState: &st, language: Language(rawValue: "de"))
                rechen.append(Date().timeIntervalSince(tr))
                if !r.text.isEmpty && ersteZeit == nil { ersteZeit = Date().timeIntervalSince(t0) }
                letzteVorschau = r.text
            }
            // naechster Durchlauf eine Sekunde nach dem Start dieses Durchlaufs
            let rest = 1.0 - (Date().timeIntervalSince(t0) - jetzt)
            if rest > 0 { try await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
        }
        var st = TdtDecoderState.make()
        let te = Date()
        let final = try await mgr.transcribe(audio, decoderState: &st, language: Language(rawValue: "de")).text
        let nachLos = Date().timeIntervalSince(te)
        print("NEU[\(name)] erster Text nach \(ersteZeit.map { String(format: "%.1f s", $0) } ?? "–") · \(rechen.count) Vorschauen · Rechenzeit je Durchlauf Ø \(String(format: "%.2f", rechen.reduce(0,+)/Double(max(1,rechen.count)))) s, max \(String(format: "%.2f", rechen.max() ?? 0)) s")
        print("       WER Endtext \(pct(wer(ref, final))) · Vorschau beim Loslassen WER \(pct(wer(ref, letzteVorschau))) · Umspringen \(pct(wer(final, letzteVorschau))) · fertig \(String(format: "%.2f", nachLos)) s nach Loslassen")
    }
}
