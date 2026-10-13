import AppKit
import Carbon
import os

private let alternativesLog = Logger(subsystem: "com.tippi.app", category: "autocomplete")

/// Alternativen mitten im Wort: ↓ zeigt drei Wörter, 1–3 setzt eines ein.
/// Regeln und Messung in `AutocompleteAlternatives`. Protokolliert werden nur
/// Anzahl, Index und Dauer — nie Wörter.
extension AutocompleteController {

    func clearAlternatives() {
        alternativesSeed = nil
        alternatives = []
        bridge.setAlternatives(seedAvailable: false, listCount: 0)
    }

    /// ↓ wurde geschluckt. Die weiteren Kandidaten werden erst jetzt zu ganzen
    /// Wörtern ergänzt (wenige kurze Anfragen an den eigenen Server).
    func showAlternatives() {
        let engine = activeEngine()
        let server = MLXServerManager.shared.ownedServerURL
        guard let entry = alternativesSeed,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.pid,
              engine != nil || server != nil else {
            dismiss()
            return
        }
        let model = engine?.model ?? MLXServerManager.activeModel
        let gen = generation
        let started = Date()
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            guard let self else { return }
            let others = await AutocompleteHealingRun(server: server, model: model, fetch: self.fetchData,
                                                      engine: engine)
                .alternativeWords(for: entry.seed)
            guard !Task.isCancelled, gen == self.generation, self.alternativesSeed?.seed == entry.seed else { return }
            let words = AutocompleteAlternatives.list(first: entry.seed.firstWord, others: others)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            alternativesLog.notice("alternatives count=\(words.count, privacy: .public) ms=\(ms, privacy: .public)")
            guard words.count > 1 else {
                // Nichts Besseres gefunden: der Vorschlag bleibt wie er war.
                self.bridge.setVisible(true)
                return
            }
            self.alternatives = words
            self.bridge.setAlternatives(seedAvailable: false, listCount: words.count)
            let fontSize = AutocompleteGeometry.fontSize(reported: entry.field.fontSize,
                                                         caretHeight: entry.field.caret.height)
            self.panel.show(AutocompleteAlternatives.label(words), caret: entry.field.caret,
                            fontSize: fontSize,
                            hint: .init(key: "1–\(words.count)", label: "1–\(words.count)"), animated: false)
        }
    }

    /// Eine Ziffer 1–3 wurde geschluckt: das Wort ohne den getippten Anfang einfügen.
    func chooseAlternative(_ index: Int) {
        let front = NSWorkspace.shared.frontmostApplication
        guard alternatives.indices.contains(index), let entry = alternativesSeed,
              front?.processIdentifier == entry.pid, !IsSecureEventInputEnabled() else {
            dismiss()
            return
        }
        let insert = AutocompleteAlternatives.insertion(word: alternatives[index], started: entry.seed.started)
        cancelPending()
        dismiss()
        alternativesLog.notice("alternative chosen index=\(index, privacy: .public) len=\(insert.count, privacy: .public)")
        guard !insert.isEmpty else { return }
        Task { await TextInsertion.replace(with: insert, in: front) }
    }

    /// Andere Taste bei offener Liste: schließen, die Taste geht normal weiter.
    func closeAlternatives() {
        dismiss(animated: true)
    }
}
