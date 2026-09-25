import Foundation

struct OpenAIProvider: OpenAICompatibleProvider {
    let id = "openai"
    let displayName = "OpenAI"
    // Default = `gpt-6-luna`: the cheapest/fastest of OpenAI's current models
    // ($0.10/$0.50 per MTok, half of gpt-5.6-luna) — best fit for Tippi's
    // "fix this short text, return the result" use case. Sent with
    // `reasoning_effort: "none"` (see below), otherwise it would think at
    // "medium" on every call. Until 2026-09-25 this was `gpt-5.6-luna`, before
    // 2026-09-02 `gpt-4o-mini`. Users can pick a larger model in the picker.
    let defaultModel = "gpt-6-luna"
    let requiresAPIKey = true

    let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Reasoning-family models (gpt-5*, gpt-6*, o1*, o3*, o4*) reject a custom
    /// temperature — return nil so the field is omitted; 0.3 for the rest.
    /// Exception: a model sent with `reasoning_effort: "none"` accepts it
    /// again (OpenAI docs: "When reasoning effort is not `none`, remove
    /// `temperature`").
    func temperature(for model: String) -> Double? {
        if Self.reasoningEffortNone(model) { return 0.3 }
        return Self.isReasoningModel(model) ? nil : 0.3
    }

    func reasoningEffort(for model: String) -> String? {
        Self.reasoningEffortNone(model) ? "none" : nil
    }

    /// gpt-6 Sol and Luna support `reasoning_effort: "none"`; gpt-6 Astra does
    /// not (OpenAI's latest-model guide, checked 2026-09-25). Astra and
    /// everything else keeps its default effort.
    static func reasoningEffortNone(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("gpt-6-sol") || lower.hasPrefix("gpt-6-luna")
    }

    /// OpenAI's reasoning-family models reject any `temperature` value other
    /// than the default (1.0) unless reasoning is switched off.
    private static func isReasoningModel(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("gpt-5")
            || lower.hasPrefix("gpt-6")
            || lower.hasPrefix("o1")
            || lower.hasPrefix("o3")
            || lower.hasPrefix("o4")
    }
}
