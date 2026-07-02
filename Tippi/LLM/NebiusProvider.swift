import Foundation

/// Nebius AI Studio — OpenAI-compatible API with 100 % EU data residency
/// (Amsterdam). DSGVO-compliant alternative to Groq for latency-sensitive
/// European use cases. Hosts open-weight models (Llama 3.x, Qwen, DeepSeek)
/// on European infrastructure.
///
/// Pricing (2026-07): ~$0.10–0.30 per 1M tokens depending on model.
/// EU invoicing available.
///
/// API keys: studio.nebius.ai
struct NebiusProvider: LLMProvider {
    let id = "nebius"
    let displayName = "Nebius (EU)"
    /// Llama 3.3 70B fast — best quality/speed balance in EU.
    let defaultModel = "meta-llama/Meta-Llama-3.3-70B-Instruct-fast"
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.studio.nebius.ai/v1/chat/completions")!

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
