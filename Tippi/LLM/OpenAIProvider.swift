import Foundation

struct OpenAIProvider: OpenAICompatibleProvider {
    let id = "openai"
    let displayName = "OpenAI"
    // Default = `gpt-5.6-luna`: the cheapest/fastest of the gpt-5.6 trio —
    // best fit for Tippi's "fix this short text, return the result" use case.
    // Until 2026-09-02 this was `gpt-4o-mini`, picked for the same reason;
    // it is no longer in OpenAI's model list. Users can pick a larger model
    // in the model picker.
    let defaultModel = "gpt-5.6-luna"
    let requiresAPIKey = true

    let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Reasoning-family models (gpt-5*, o1*, o3*, o4*) reject a custom
    /// temperature — return nil so the field is omitted; 0.3 for the rest.
    func temperature(for model: String) -> Double? {
        Self.isReasoningModel(model) ? nil : 0.3
    }

    /// OpenAI's reasoning-family models (gpt-5*, o1*, o3*, o4*) reject any
    /// `temperature` value other than the default (1.0).
    private static func isReasoningModel(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("gpt-5")
            || lower.hasPrefix("o1")
            || lower.hasPrefix("o3")
            || lower.hasPrefix("o4")
    }
}
