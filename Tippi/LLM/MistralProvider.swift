import Foundation

struct MistralProvider: LLMProvider {
    let id = "mistral"
    let displayName = "Mistral"
    let defaultModel = "mistral-small-latest"  // alias auto-updates to current small model
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")!

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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
        }
        let body = Body(
            model: model.isEmpty ? defaultModel : model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userText)
            ],
            temperature: 0.3
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
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String }
                let message: Msg
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
