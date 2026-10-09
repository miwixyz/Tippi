import Foundation

struct AnthropicProvider: LLMProvider {
    let id = "anthropic"
    let displayName = "Anthropic Claude"
    let defaultModel = "claude-haiku-4-5"  // still the measured best for polish, 2026-10-09
    let requiresAPIKey = true

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userText: userText, model: model, temperature: nil)
    }

    /// Claude models from Opus 4.7 / Sonnet 5 on reject `temperature` with a
    /// 400 — sampling is removed there. Only the older generation takes it.
    static func acceptsTemperature(_ model: String) -> Bool {
        ["claude-haiku-4", "claude-sonnet-4", "claude-opus-4-5", "claude-opus-4-6", "claude-opus-4-1", "claude-3"]
            .contains { model.hasPrefix($0) }
    }

    /// Haiku 5.5 thinks by default (adaptive, effort `medium`): one polish run took
    /// 3.6 s / 620 tokens instead of ~1.2 s (measured 2026-10-09). For Tippi's short
    /// rewrites: effort `low` and thinking off — allowed up to effort `high`
    /// (platform.claude.com/docs/en/build-with-claude/effort).
    static func usesLowEffortNoThinking(_ model: String) -> Bool {
        model.hasPrefix("claude-haiku-5")
    }

    func complete(systemPrompt: String, userText: String, model: String,
                  temperature hint: Double?) async throws -> String {
        let apiKey: String? = await MainActor.run {
            try? KeychainStore.getAPIKey(for: id)
        }
        guard let apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey(provider: displayName)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct OutputConfig: Encodable { let effort: String }
        struct Thinking: Encodable { let type: String }
        struct Body: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
            let temperature: Double?   // nil → omitted from the JSON
            let output_config: OutputConfig?
            let thinking: Thinking?
        }
        let useModel = model.isEmpty ? defaultModel : model
        let body = Body(
            model: useModel,
            max_tokens: 8192,
            system: systemPrompt,
            messages: [Message(role: "user", content: userText)],
            temperature: Self.acceptsTemperature(useModel) ? hint : nil,
            output_config: Self.usesLowEffortNoThinking(useModel) ? OutputConfig(effort: "low") : nil,
            thinking: Self.usesLowEffortNoThinking(useModel) ? Thinking(type: "disabled") : nil
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
            let stop_reason: String?
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        // A truncated rewrite must never be inserted — it would silently
        // destroy the tail of the user's selection.
        guard decoded.stop_reason != "max_tokens" else { throw LLMError.truncated }
        // Haiku 5.5 runs safety classifiers and may decline without a fallback.
        guard decoded.stop_reason != "refusal" else {
            throw LLMError.providerError(message: "Claude declined this request (refusal).")
        }
        let text = decoded.content.compactMap { block in
            block.type == "text" ? block.text : nil
        }.joined()
        guard !text.isEmpty else { throw LLMError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Anthropic's `/v1/models` shares the same `{"data":[{"id":…}]}` shape
    /// as the OpenAI-compatible providers, just under a different auth
    /// scheme (`x-api-key` + `anthropic-version`, not `Authorization: Bearer`).
    ///
    /// `limit=1000` (the documented maximum) is essential, not cosmetic: the
    /// endpoint defaults to **20** and sorts newest-first, so without it a
    /// perfectly working older model like `claude-haiku-4-5` simply isn't in
    /// the response and gets reported as retired. That exact false alarm
    /// shipped in v1.21.0 and was caught on 2026-09-02. `has_more` is still
    /// honoured on top, so a future catalogue past 1000 degrades to
    /// "incomplete" (no warning) instead of lying.
    func fetchModelCatalog() async throws -> ModelCatalog {
        let apiKey: String? = await MainActor.run { try? KeychainStore.getAPIKey(for: id) }
        guard let apiKey, !apiKey.isEmpty else { throw LLMError.noAPIKey(provider: displayName) }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse
        }
        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
            let has_more: Bool?
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return ModelCatalog(
            ids: Set(decoded.data.map(\.id)),
            isComplete: decoded.has_more != true
        )
    }
}
