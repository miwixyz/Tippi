// Hilfsprogramm für scripts/antwort-pruefstand.py: schickt EINE Anfrage an Apple
// Intelligence über dieselbe Datei, die in der App steckt (Tippi/LLM/AppleIntelligenceModel.swift).
//
// Eingabe auf stdin: JSON {"instructions": "...", "text": "...", "temperature": 0.3}
// Ausgabe auf stdout: die Antwort. Fehler: Meldung auf stderr, Exit 1 (Exit 2 = nicht verfügbar).
//
// Bauen (aus dem Repo-Wurzelordner):
//   xcrun swiftc -O -o "$TMPDIR/tippi-antwort-apple" \
//     scripts/antwort-pruefstand-apple/main.swift Tippi/LLM/AppleIntelligenceModel.swift

import Foundation

struct Request: Decodable {
    let instructions: String
    let text: String
    let temperature: Double?
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let request = try? JSONDecoder().decode(Request.self, from: input) else {
    FileHandle.standardError.write(Data("✗ Eingabe kein gültiges JSON\n".utf8))
    exit(1)
}
if let reason = AppleIntelligenceModel.unavailableReason {
    FileHandle.standardError.write(Data("✗ Apple Intelligence nicht verfügbar: \(reason)\n".utf8))
    exit(2)
}

let done = DispatchSemaphore(value: 0)
var status: Int32 = 0
Task {
    do {
        let out = try await AppleIntelligenceModel.respond(
            instructions: request.instructions, text: request.text,
            sampling: AppleIntelligenceModel.sampling(forTemperatureHint: request.temperature))
        print(out)
    } catch {
        FileHandle.standardError.write(Data("✗ FEHLER \(error)\n".utf8))
        status = 1
    }
    done.signal()
}
done.wait()
exit(status)
