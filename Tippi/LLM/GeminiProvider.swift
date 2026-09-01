import Foundation

struct GeminiProvider: LLMProvider {
    let id = "gemini"
    let displayName = "Google Gemini"
    // gemini-2.5-flash returns HTTP 404 for accounts without prior grandfathered
    // access ("no longer available to new users" — confirmed via a real Tippi
    // error + Google's own migration pointer + ai.google.dev docs, 2026-09-01).
    // gemini-3.5-flash is Google's stated GA replacement for the same tier.
    let defaultModel = "gemini-3.5-flash"
    let requiresAPIKey = true

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        let apiKey: String? = await MainActor.run {
            try? KeychainStore.getAPIKey(for: id)
        }
        guard let apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey(provider: displayName)
        }

        // The model name comes from a free-form settings text field — percent-
        // encode it so e.g. a stray space can't produce a nil URL (crash).
        let useModel = model.isEmpty ? defaultModel : model
        guard let encodedModel = useModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string:
                  "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent"
              ) else {
            throw LLMError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
                // content/parts can be absent when the generation was blocked
                // (SAFETY) or cut off (MAX_TOKENS) — keep optional so decoding
                // doesn't fail before we can report the real cause.
                let content: Content?
                let finishReason: String?
            }
            let candidates: [Candidate]?
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let candidate = decoded.candidates?.first else {
            throw LLMError.invalidResponse
        }
        // A truncated rewrite must never be inserted — it would silently
        // destroy the tail of the user's text.
        guard candidate.finishReason != "MAX_TOKENS" else { throw LLMError.truncated }
        guard let text = candidate.content?.parts.first?.text else {
            throw LLMError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
