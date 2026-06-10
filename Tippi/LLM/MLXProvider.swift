import Foundation

struct MLXProvider: LLMProvider {
    let id           = "mlx"
    let displayName  = "MLX (local)"
    let defaultModel = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    let requiresAPIKey = false

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        // Ensure server is running (starts it if needed)
        let port = try await MLXServerManager.shared.start()
        let url  = URL(string: "http://localhost:\(port)/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90  // startup is handled separately; keep running requests bounded
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let stream: Bool
            let max_tokens: Int
            let temperature: Double
        }
        // Use the HuggingFace repo ID we explicitly started the server with —
        // NOT whatever /v1/models reports first.
        //
        // mlx_lm.server's /v1/models lists every model in the HF cache, in
        // arbitrary order. Picking data[0] (the old behaviour) was wrong
        // whenever the user had more than one model downloaded: the API call
        // would request a different model than the one --model launched the
        // server with, forcing a full model swap on every transformation and
        // hanging the UI forever.
        //
        // Since MLXServerManager always launches mlx_lm.server with
        // `--model <configured>`, that exact ID is guaranteed to be valid.
        let resolvedModel = await MainActor.run { MLXServerManager.activeModel }
        let body = Body(
            model: resolvedModel,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user",   content: userText)
            ],
            stream: false,
            max_tokens: maxTokens(for: userText),
            temperature: 0.3
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
            struct Msg: Decodable {
                let content: String?
                let reasoning: String?  // Thinking-Modelle (Qwen3.5 etc.) liefern reasoning statt content
            }
            let message: Msg
            let finish_reason: String?
        }
        struct ResponseBody: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let first = decoded.choices.first else { throw LLMError.invalidResponse }
        // A truncated rewrite must never be inserted — it would silently
        // destroy the tail of the user's selection.
        guard first.finish_reason != "length" else { throw LLMError.truncated }
        let text = first.message.content ?? first.message.reasoning ?? ""
        guard !text.isEmpty else { throw LLMError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func maxTokens(for userText: String) -> Int {
        // Most Tippi operations rewrite or summarize; a capped dynamic budget
        // keeps local models from drifting into slow, overly long completions.
        let approximateInputTokens = max(1, userText.count / 4)
        return min(2048, max(256, approximateInputTokens * 2))
    }
}
