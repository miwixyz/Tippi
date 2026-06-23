import Foundation

/// Scaleway Generative APIs — EU-hosted (Paris) chat completions endpoint
/// with OpenAI-compatible request/response schema. Backs Llama 3.x and
/// Mistral-derived models on dedicated EU infrastructure → covers both
/// speed and GDPR/DSGVO requirements that hosted US providers can't.
///
/// Llama 3.1 8B Instruct on Scaleway clocks ~300 tokens/sec, Llama 3.3 70B
/// ~250 tokens/sec — Groq-class throughput while staying on EU soil.
struct ScalewayProvider: LLMProvider {
    let id = "scaleway"
    let displayName = "Scaleway (EU)"
    /// Default = Llama 3.1 8B Instruct: fastest on Scaleway, sub-second
    /// polish, acceptable German. Pick the 70B preset for premium quality.
    let defaultModel = "llama-3.1-8b-instruct"
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.scaleway.ai/v1/chat/completions")!

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        let apiKey = try await keychainAPIKey(id: id, displayName: displayName)
        return try await openAIChatComplete(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model.isEmpty ? defaultModel : model,
            systemPrompt: systemPrompt,
            userText: userText,
            temperature: 0.3
        )
    }

    func completeStream(systemPrompt: String, userText: String, model: String) -> AsyncThrowingStream<String, Error> {
        openAIProviderStream(
            id: id, displayName: displayName, endpoint: endpoint,
            model: model.isEmpty ? defaultModel : model,
            systemPrompt: systemPrompt, userText: userText, temperature: 0.3
        )
    }
}
