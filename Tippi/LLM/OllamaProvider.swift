import Foundation

struct OllamaProvider: LLMProvider {
    let id = "ollama"
    let displayName = "Ollama (local)"
    let defaultModel = "llama3.3"
    let requiresAPIKey = false

    private let endpoint = URL(string: "http://localhost:11434/api/chat")!

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let stream: Bool
        }
        let body = Body(
            model: model.isEmpty ? defaultModel : model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userText)
            ],
            stream: false
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
            struct Msg: Decodable { let content: String }
            let message: Msg
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
