import Foundation

struct MLXProvider: LLMProvider {
    let id           = "mlx"
    let displayName  = "MLX (local)"
    let defaultModel = "mlx-community/Qwen3.5-2B-MLX-8bit"
    let requiresAPIKey = false

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        // Ensure server is running (starts it if needed)
        let port = try await MLXServerManager.shared.start()
        let url  = URL(string: "http://localhost:\(port)/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120  // local models can be slow on first token
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let stream: Bool
            let max_tokens: Int
        }
        let resolvedModel = model.isEmpty
            ? await MainActor.run { MLXServerManager.model }
            : model
        let body = Body(
            model: resolvedModel,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user",   content: userText)
            ],
            stream: false,
            max_tokens: 2048
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(status: http.statusCode, body: text)
        }

        // OpenAI-compatible response shape
        struct Choice: Decodable {
            struct Msg: Decodable { let content: String }
            let message: Msg
        }
        struct ResponseBody: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let first = decoded.choices.first else { throw LLMError.invalidResponse }
        return first.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
