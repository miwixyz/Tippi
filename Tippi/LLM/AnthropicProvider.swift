import Foundation

struct AnthropicProvider: LLMProvider {
    let id = "anthropic"
    let displayName = "Anthropic Claude"
    let defaultModel = "claude-haiku-4-5"  // current as of May 2026
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        let apiKey: String? = await MainActor.run {
            try? KeychainStore.getAPIKey(for: id)
        }
        guard let apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey(provider: displayName)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
        }
        let body = Body(
            model: model.isEmpty ? defaultModel : model,
            max_tokens: 2048,
            system: systemPrompt,
            messages: [Message(role: "user", content: userText)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(status: http.statusCode, body: text)
        }

        struct ResponseBody: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content.compactMap { block in
            block.type == "text" ? block.text : nil
        }.joined()
        guard !text.isEmpty else { throw LLMError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
