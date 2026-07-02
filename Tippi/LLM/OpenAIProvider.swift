import Foundation

struct OpenAIProvider: OpenAICompatibleProvider {
    let id = "openai"
    let displayName = "OpenAI"
    /// Default = `gpt-4o-mini`: fast, cheap, non-reasoning — best fit for
    /// Tippi's "fix this short text, return the result" use case. The
    /// gpt-5* reasoning family adds thinking-token latency that hurts the
    /// dictation/transform UX. Users can opt into reasoning in the model
    /// picker.
    let defaultModel = "gpt-4o-mini"
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
