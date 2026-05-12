import Foundation

struct GeminiProvider: LLMProvider {
    let id = "gemini"
    let displayName = "Google Gemini"
    let defaultModel = "gemini-2.0-flash"
    let requiresAPIKey = true

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        let apiKey: String? = await MainActor.run {
            try? KeychainStore.getAPIKey(for: id)
        }
        guard let apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey(provider: displayName)
        }

        let useModel = model.isEmpty ? defaultModel : model
        let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(useModel):generateContent?key=\(apiKey)"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Part: Encodable { let text: String }
        struct Content: Encodable { let parts: [Part] }
        struct SystemInstruction: Encodable { let parts: [Part] }
        struct Body: Encodable {
            let system_instruction: SystemInstruction
            let contents: [Content]
        }
        let body = Body(
            system_instruction: SystemInstruction(parts: [Part(text: systemPrompt)]),
            contents: [Content(parts: [Part(text: userText)])]
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
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = decoded.candidates?.first?.content.parts.first?.text else {
            throw LLMError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
