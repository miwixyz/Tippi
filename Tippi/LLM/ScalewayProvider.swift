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
