import Foundation

struct OpenAIProvider: LLMProvider {
    let id = "openai"
    let displayName = "OpenAI"
    /// Default = `gpt-4o-mini`: fast, cheap, non-reasoning — best fit for
    /// Tippi's "fix this short text, return the result" use case. The
    /// gpt-5* reasoning family adds thinking-token latency that hurts the
    /// dictation/transform UX. Users can opt into reasoning in the model
    /// picker.
    let defaultModel = "gpt-4o-mini"
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        let apiKey = try await keychainAPIKey(id: id, displayName: displayName)
        let modelName = model.isEmpty ? defaultModel : model
        // Reasoning-family models (gpt-5*, o1*, o3*, o4*) reject a custom
        // temperature — send nil so the field is omitted; 0.3 for the rest.
        let temperature: Double? = Self.isReasoningModel(modelName) ? nil : 0.3
        return try await openAIChatComplete(
            endpoint: endpoint,
            apiKey: apiKey,
            model: modelName,
            systemPrompt: systemPrompt,
            userText: userText,
            temperature: temperature
        )
    }

    func completeStream(systemPrompt: String, userText: String, model: String) -> AsyncThrowingStream<String, Error> {
        let modelName = model.isEmpty ? defaultModel : model
        let temperature: Double? = Self.isReasoningModel(modelName) ? nil : 0.3
        return openAIProviderStream(
            id: id, displayName: displayName, endpoint: endpoint,
            model: modelName,
            systemPrompt: systemPrompt, userText: userText, temperature: temperature
        )
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
