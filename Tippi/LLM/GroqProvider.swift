import Foundation

/// Groq Cloud — OpenAI-compatible chat completions endpoint backed by Groq's
/// LPU inference hardware. Hosted Llama / GPT-OSS models stream at 270–800
/// tokens/sec, making this the fastest hosted provider for short-text tasks
/// like dictation polishing (sub-second round-trip in practice).
struct GroqProvider: LLMProvider {
    let id = "groq"
    let displayName = "Groq"
    /// Llama 3.3 70B Versatile — strong quality at ~270 tok/s. The
    /// `llama-3.1-8b-instant` preset is faster (~800 tok/s) when latency
    /// matters more than quality.
    let defaultModel = "llama-3.3-70b-versatile"
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

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
