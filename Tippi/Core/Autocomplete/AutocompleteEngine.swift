import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import os

private let engineLog = Logger(subsystem: "com.tippi.app", category: "autocomplete")

// MARK: - Rechenwerk im eigenen Prozess

/// Rechnet die Autovervollständigung direkt in Tippi (MLX Swift) statt über
/// `mlx_lm.server` — Design `docs/SECURE-DESIGN-autocomplete.md` §10.
///
/// **Warum (gemessen 2026-10-13, Spike `~/Coding/tippi-mlx-spike`):** Wortheilung
/// mit Gemma 4 E4B 0,32 s statt 0,77 s über den Server, E2B 0,30 s statt
/// 0,45–0,66 s. Der mlx-lm-Hänger („vorige Anfrage + Antwort") tritt im Prozess
/// nicht auf. Wortheilung, Alternativen und Fortsetzung laufen in **einem**
/// Durchgang über denselben Rechen-Cache.
///
/// Läuft nie auf dem Hauptthread (eigener Actor). Getippter Text bleibt im
/// Speicher, nichts wird protokolliert außer Zeiten und Anzahlen.
actor AutocompleteEngine {
    let model: String
    private let context: ModelContext
    private let stops: Set<Int>

    /// MLX hält berechnete Zwischenergebnisse; in einer Menüleisten-App klein halten.
    static let cacheLimitBytes = 256 * 1024 * 1024

    struct Result {
        /// Rest des angefangenen Wortes ("ingen"); leer am Wortanfang.
        let tail: String
        /// Freie Fortsetzung danach.
        let continuation: String
        /// An der Längengrenze beendet (nicht von selbst).
        let cutAtLength: Bool
        /// Kandidaten fürs erste Stück (Alternativen), wahrscheinlichste zuerst.
        let candidates: [Int]
    }

    private init(model: String, context: ModelContext) {
        self.model = model
        self.context = context
        let tokenizer = context.tokenizer
        self.stops = Set([tokenizer.eosToken, "<turn|>", "<eos>"].compactMap { $0 }
            .compactMap { tokenizer.convertTokenToId($0) })
    }

    /// Lädt das Modell aus dem Hugging-Face-Zwischenspeicher — nie aus dem Netz.
    static func load(model: String, hub: URL = AutocompleteVocabulary.hubDirectory) async throws -> AutocompleteEngine {
        guard let snapshot = snapshotDirectory(model: model, hub: hub) else { throw EngineError.modelNotCached }
        Memory.cacheLimit = cacheLimitBytes
        let context = try await LLMModelFactory.shared.load(from: snapshot, using: TransformersTokenizerLoader())
        return AutocompleteEngine(model: model, context: context)
    }

    enum EngineError: Error { case modelNotCached }

    /// Snapshot-Ordner mit `config.json` und Gewichten — oder `nil`.
    static func snapshotDirectory(model: String, hub: URL = AutocompleteVocabulary.hubDirectory) -> URL? {
        guard let folder = AutocompleteVocabulary.cacheFolder(for: model) else { return nil }
        let snapshots = hub.appendingPathComponent(folder).appendingPathComponent("snapshots")
        let candidates = (try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? []
        return candidates.first { dir in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return files.contains("config.json") && files.contains { $0.hasSuffix(".safetensors") }
        }
    }

    /// Wortheilung (Stücke auf den getippten Anfang `open` beschränkt) und danach
    /// freie Fortsetzung, in einem Durchgang. `nil`, wenn kein passendes Stück kommt.
    func run(prompt: String, open: String, vocabulary: AutocompleteVocabulary,
             maxSteps: Int, maxTokens: Int, candidates: Int) throws -> Result? {
        let cache = try context.model.newCache(parameters: nil)
        var logits = forward(context.tokenizer.encode(text: prompt, addSpecialTokens: true), cache: cache)
        var rest = open
        var tail: String? = open.isEmpty ? "" : nil
        var found: [Int] = []
        var steps = 0
        while tail == nil, steps < maxSteps {
            try Task.checkCancellation()
            steps += 1
            let allowed = vocabulary.allowedIDs(rest: rest)
            guard !allowed.isEmpty else { return nil }
            let row = logits[0, -1, 0...]
            let masked = row + Self.mask(allowed, size: row.dim(0))
            if steps == 1, candidates > 0 { found = Self.top(masked, count: candidates) }
            let next = argMax(masked, axis: -1).item(Int.self)
            guard let piece = vocabulary.piece(next) else { return nil }
            switch AutocompleteWordHealing.step(rest: rest, piece: piece) {
            case .finished(let wordTail): tail = wordTail
            case .partial(let open): rest = open
            case .mismatch: return nil
            }
            logits = forward([next], cache: cache)
        }
        guard let tail else { return nil }
        let free = try freeRun(logits: logits, cache: cache, maxTokens: maxTokens)
        return Result(tail: tail, continuation: free.text, cutAtLength: free.cutAtLength, candidates: found)
    }

    /// Freie Fortsetzung eines Prompts (Alternativen zu ganzen Wörtern ergänzen).
    func complete(prompt: String, maxTokens: Int) throws -> (text: String, cutAtLength: Bool) {
        let cache = try context.model.newCache(parameters: nil)
        let logits = forward(context.tokenizer.encode(text: prompt, addSpecialTokens: true), cache: cache)
        return try freeRun(logits: logits, cache: cache, maxTokens: maxTokens)
    }

    private func freeRun(logits start: MLXArray, cache: [KVCache], maxTokens: Int) throws -> (text: String, cutAtLength: Bool) {
        var logits = start
        var out: [Int] = []
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            let next = argMax(logits[0, -1, 0...], axis: -1).item(Int.self)
            if stops.contains(next) {
                return (context.tokenizer.decode(tokenIds: out, skipSpecialTokens: true), false)
            }
            out.append(next)
            logits = forward([next], cache: cache)
        }
        return (context.tokenizer.decode(tokenIds: out, skipSpecialTokens: true), true)
    }

    private func forward(_ tokens: [Int], cache: [KVCache]) -> MLXArray {
        context.model(MLXArray(tokens.map { Int32($0) })[.newAxis, 0...], cache: cache)
    }

    private static func mask(_ allowed: [Int], size: Int) -> MLXArray {
        var values = [Float](repeating: -1e9, count: size)
        for id in allowed where id >= 0 && id < size { values[id] = 0 }
        return MLXArray(values)
    }

    private static func top(_ row: MLXArray, count: Int) -> [Int] {
        let order = argSort(-row, axis: -1)
        return order[0 ..< min(count, row.dim(0))].asArray(Int32.self).map(Int.init)
    }
}

// MARK: - Tokenizer (swift-transformers, ohne Makro)

/// Lädt den Tokenizer aus dem Modellordner. Chat-Vorlagen (Jinja) werden nie
/// ausgeführt — Tippi baut den Prompt selbst (`AutocompleteWordHealing.prompt`).
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
}

// MARK: - Verwaltung (laden, entladen)

/// Hält höchstens ein Rechenwerk und lädt es im Hintergrund. Solange es lädt
/// oder nicht ladbar ist, bleibt die Autovervollständigung beim Server-Weg.
@MainActor
final class AutocompleteEngineHost {
    private var engine: AutocompleteEngine?
    private var loading: String?
    private var failed: Set<String> = []

    /// Bevorzugt E4B (gemessen treffsicherer), sonst E2B — nur was schon im
    /// Zwischenspeicher liegt. Tippi lädt nichts herunter.
    static let preferredModels = ["mlx-community/gemma-4-e4b-it-4bit", "mlx-community/gemma-4-e2b-it-4bit"]

    static func availableModel() -> String? {
        preferredModels.first { AutocompleteEngine.snapshotDirectory(model: $0) != nil }
    }

    func engine(for model: String) -> AutocompleteEngine? {
        if let engine, engine.model == model { return engine }
        guard loading != model, !failed.contains(model) else { return nil }
        loading = model
        engine = nil
        Task { [weak self] in
            let started = Date()
            do {
                let loaded = try await AutocompleteEngine.load(model: model)
                // Aufwärmen: Der erste Durchlauf übersetzt die Metal-Rechenschritte —
                // gemessen 2026-10-13 dauerte der erste echte Vorschlag sonst 5,1 s
                // (Median danach 0,5 s). Text ohne Bezug zum Getippten.
                _ = try? await loaded.complete(prompt: "Guten Morgen", maxTokens: 2)
                guard let self, self.loading == model else { return }
                self.engine = loaded
                self.loading = nil
                engineLog.notice("engine loaded model=\(model, privacy: .public) ms=\(Int(Date().timeIntervalSince(started) * 1000), privacy: .public)")
            } catch {
                guard let self else { return }
                self.loading = nil
                self.failed.insert(model)
                engineLog.error("engine load failed model=\(model, privacy: .public)")
            }
        }
        return nil
    }

    /// Modell aus dem Speicher nehmen (Schalter aus / Autovervollständigung aus).
    func unload() {
        guard engine != nil || loading != nil else { return }
        engine = nil
        loading = nil
        Memory.clearCache()
        engineLog.notice("engine unloaded")
    }
}

// MARK: - Schalter

extension AutocompleteController {
    /// Labs-Schalter „Direkt in Tippi rechnen": an → im Hintergrund laden,
    /// aus → Modell aus dem Speicher nehmen.
    func setInProcess(_ on: Bool) {
        AutocompleteSettings.inProcess = on
        if on, isEnabled { _ = activeEngine() } else { engines.unload() }
    }
}
