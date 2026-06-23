import Foundation

struct MistralProvider: LLMProvider {
    let id = "mistral"
    let displayName = "Mistral"
    let defaultModel = "mistral-small-latest"  // alias auto-updates to current small model
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")!

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
