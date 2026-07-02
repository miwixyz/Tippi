import Foundation

/// Moonshot Kimi K2 — OpenAI-compatible chat completions API.
///
/// Kimi K2 is a 1T-parameter MoE model (Modified MIT open-weight) with 256K
/// context and MoonViT vision. Leads SWE-Bench Pro (58.6) ahead of GPT-5.4
/// and Claude Opus 4.5. ~15× cheaper than Opus at comparable coding quality.
///
/// Pricing (direct API, 2026-07): $0.95 / $4.00 per 1M tokens in/out.
/// Cache-hit input: $0.16. OpenRouter alternative: $0.80 / $3.40.
///
/// API keys: platform.moonshot.cn
struct KimiProvider: LLMProvider {
    let id = "kimi"
    let displayName = "Kimi (Moonshot)"
    /// Kimi K2 — flagship model, 256K context, leading SWE-Bench Pro.
    let defaultModel = "kimi-k2"
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.moonshot.cn/v1/chat/completions")!

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
