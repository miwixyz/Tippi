import AppKit

/// Diktat-Modi im Ablauf des Diktats (`DictationModes`). Eigene Datei, damit
/// `DictationController.swift` unter seiner Längengrenze bleibt und die Modi an
/// einer Stelle stehen.
extension DictationController {
    /// Läuft nach dem Sprechen ein KI-Schritt? Für die Anzeige.
    var aiStepPlanned: Bool { source.dictationMode != nil || DictationSettings.postProcessEnabled }

    /// Statt `postProcessIfEnabled`: ohne Modus genau das, mit Modus dessen Prompt.
    /// „Verbessern" ist die normale Glättung, aber unabhängig vom Schalter und ohne
    /// Mindestlänge — der Nutzer hat den Modus ausdrücklich gewählt.
    func processTranscript(_ raw: String, appName: String) async -> (text: String, notice: String?) {
        guard let mode = source.dictationMode else { return await postProcessIfEnabled(raw) }
        switch mode.action {
        case .improve:
            return await postProcessIfEnabled(raw, forced: true)
        case .prompt(let prompt):
            return await runPromptMode(prompt, raw: raw, appName: appName)
        }
    }

    /// Wie `warmPostProcessProviderIfNeeded`, aber mit dem Prompt des Modus.
    /// `false` = kein Modus, der Aufrufer wärmt wie bisher.
    func warmModeProviderIfNeeded() -> Bool {
        guard let mode = source.dictationMode else { return false }
        let target: (providerID: String, prompt: String)
        switch mode.action {
        case .improve:
            let override = DictationSettings.postProcessProviderOverride
            target = (override.isEmpty ? LLMRouter.shared.effectivePreferredProviderID() : override,
                      DictationSettings.effectivePostProcessPrompt)
        case .prompt(let prompt):
            // Eine Kette beginnt mit ihrem ersten Schritt, über die normale Auflösung.
            let first = prompt.pipeline?.first.flatMap(DemoPrompt.resolve(id:))
            let provider = first == nil ? PromptProviderOverride.effectiveProviderID(for: prompt.id)
                                        : LLMRouter.shared.effectivePreferredProviderID()
            // Das Transkript gibt es noch nicht: `{language}` wird zum Rückfallwort. Der
            // Server hält den Prompt-Anfang bis zur ersten Abweichung im Zwischenspeicher.
            target = (provider, Self.resolvedPrompt(first ?? prompt, text: "", appName: ""))
        }
        guard target.providerID == "mlx" else { return true }
        let prompt = target.prompt
        Task.detached(priority: .utility) {
            await MLXProvider.prime(systemPrompt: prompt)
        }
        return true
    }

    /// Prompt des Modus auf das Transkript, mit derselben Anbieter-/Modellwahl wie im
    /// Pop-up (`PromptProviderOverride.complete`), demselben 30-s-Deckel und demselben
    /// Rückfall auf den Rohtext mit Hinweis wie die Glättung.
    private func runPromptMode(_ prompt: DemoPrompt, raw: String, appName: String) async -> (text: String, notice: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (raw, nil) }
        let providerID = prompt.isChain ? LLMRouter.shared.effectivePreferredProviderID()
                                        : PromptProviderOverride.effectiveProviderID(for: prompt.id)
        indicator.transcribing(recorder: recorder, aiEnabled: true,
                               providerName: LLMRouter.providerDisplayName(forID: providerID), source: source)
        do {
            let result = try await Self.withPolishDeadline {
                try await Self.run(prompt, text: trimmed, appName: appName)
            }
            let output = try LLMError.nonEmpty(result.text)
            NSLog("Tippi: dictation mode '\(prompt.id)' via \(result.providerDisplay) in \(String(format: "%.2f", result.duration))s")
            do {
                try HistoryStore.shared.append(
                    appName: "Dictation", promptTitle: prompt.title, provider: result.providerID,
                    model: result.model, language: nil, latencyMs: Int((result.duration * 1000).rounded()),
                    input: trimmed, output: output)
            } catch {
                NSLog("Tippi: history append failed — \(error.localizedDescription)")
            }
            return (output, nil)
        } catch {
            let reason = Self.cleanupFailureReason(error)
            NSLog("Tippi: dictation mode '\(prompt.id)' failed — \(reason) — keeping raw")
            return (raw, Self.cleanupFailedNotice(reason))
        }
    }

    /// Ein Prompt oder eine Kette, wie im Pop-up: Einzelschritt mit seiner Überschreibung,
    /// Kettenschritte über die normale Auflösung (`PreviewView.runChain`).
    private static func run(_ prompt: DemoPrompt, text: String, appName: String) async throws -> CompletionResult {
        guard let steps = prompt.pipeline else {
            return try await PromptProviderOverride.complete(
                promptID: prompt.id, systemPrompt: resolvedPrompt(prompt, text: text, appName: appName), userText: text)
        }
        var current = text
        var last: CompletionResult?
        for id in steps {
            guard let step = DemoPrompt.resolve(id: id) else { throw LLMError.emptyResult }
            let result = try await LLMRouter.shared.complete(
                systemPrompt: resolvedPrompt(step, text: current, appName: appName), userText: current)
            current = try LLMError.nonEmpty(result.text)
            last = result
        }
        guard let last else { throw LLMError.emptyResult }
        return last
    }

    private static func resolvedPrompt(_ prompt: DemoPrompt, text: String, appName: String) -> String {
        PromptVariableResolver.resolve(template: prompt.systemPrompt,
                                       context: PromptVariableResolver.Context(selectedText: text, appName: appName))
    }

    /// Der 30-s-Deckel der Glättung (`postProcessIfEnabled`), als Hülle.
    private static func withPolishDeadline(
        _ operation: @escaping @Sendable () async throws -> CompletionResult
    ) async throws -> CompletionResult {
        try await withThrowingTaskGroup(of: CompletionResult.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw CleanupTimeout()
            }
            guard let first = try await group.next() else { throw LLMError.cancelled }
            group.cancelAll()
            return first
        }
    }
}
