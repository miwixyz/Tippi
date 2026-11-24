import Foundation
import os

/// Warming the local MLX model for the polish step while the user speaks.
/// Own file so `DictationController.swift` stays under its length limit.
extension DictationController {
    /// Fire-and-forget: if dictation post-process is enabled and resolves to
    /// the local MLX provider, start warming its server now instead of
    /// waiting for the first real polish request. Mirrors
    /// `SpeechTranscriber.prewarm()` right above the call site — both let
    /// model loading overlap with the time the user spends speaking.
    /// Resolution mirrors `postProcessIfEnabled`: an explicit per-prompt
    /// override wins, otherwise the global default provider.
    func warmPostProcessProviderIfNeeded() {
        guard Self.postProcessUsesMLX else { return }
        // Not just start(): for an already running server that is a no-op, yet
        // the first polish after a long idle still paid the weight page-in and
        // the full prompt prefill after recording ended (20.6 s measured
        // 2026-10-27). prime() starts the server if needed AND sends the exact
        // cleanup prompt, so the real request only prefills the transcript.
        keepLocalModelWarm(prompt: DictationSettings.effectivePostProcessPrompt)
    }

    /// Läuft die Diktat-Nachbearbeitung über den lokalen MLX-Server? Gleiche Auflösung
    /// wie `postProcessIfEnabled`: Override pro Prompt gewinnt, sonst der globale Standard.
    /// Auch der Leerlauf-Entlader fragt das (`AppDelegate.wireIdleUnload`).
    static var postProcessUsesMLX: Bool {
        guard DictationSettings.postProcessEnabled else { return false }
        let override = DictationSettings.postProcessProviderOverride
        let provider = override.isEmpty ? LLMRouter.shared.effectivePreferredProviderID() : override
        return provider == "mlx"
    }

    /// Seconds between two primes while recording.
    static let keepWarmInterval: UInt64 = 2

    /// Primes the MLX server once now and again every `keepWarmInterval` seconds
    /// for as long as this recording runs, so a long dictation does not end with
    /// a cooled-down model. Measured 2026-11-16 (Mac mini, gemma-4-e4b-it-4bit):
    /// a request 30 s after the last one took +0.63 s / +0.97 s longer than one
    /// right after it (two runs), +1.6 s after 60 s — with the prompt cache
    /// intact, so it is the hardware idling down, not the cache. E2B on the
    /// MacBook showed no effect (+0.10 s); the extra primes cost little there.
    /// One prime at a time: the next one waits for the previous to finish.
    /// A warm prime costs ~0.3 s (measured 2026-11-18, E4B, 1,094 of 1,095 tokens
    /// cached), so one still running at release delays the polish by at most that.
    /// Ends once the state leaves `.recording` (stop, discard) or a prime fails —
    /// a failing server start must not be relaunched every 2 s while the user talks.
    func keepLocalModelWarm(prompt: String) {
        keepWarmTask?.cancel()
        keepWarmTask = Task { [weak self] in
            while !Task.isCancelled {
                let primed = await Task.detached(priority: .utility) {
                    await MLXProvider.prime(systemPrompt: prompt)
                }.value
                guard primed else {
                    dictationLog.notice("keep-warm stopped — local model prime failed")
                    return
                }
                try? await Task.sleep(nanoseconds: Self.keepWarmInterval * 1_000_000_000)
                guard !Task.isCancelled, let self, case .recording = self.state else { return }
            }
        }
    }

    func stopKeepingLocalModelWarm() {
        keepWarmTask?.cancel()
        keepWarmTask = nil
    }
}
