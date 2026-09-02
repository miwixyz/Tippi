import Foundation

protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var defaultModel: String { get }
    var requiresAPIKey: Bool { get }

    func complete(
        systemPrompt: String,
        userText: String,
        model: String
    ) async throws -> String

    /// Streams the completion as incremental text deltas. Providers that
    /// support server-sent events override this; the default implementation
    /// falls back to a single `complete()` call emitted as one chunk, so every
    /// provider works whether or not it streams.
    func completeStream(
        systemPrompt: String,
        userText: String,
        model: String
    ) -> AsyncThrowingStream<String, Error>

    /// Live model IDs this provider currently serves, straight from its own
    /// API — lets `ModelAvailabilityChecker` flag a configured model the
    /// provider has quietly retired (the gemini-2.5-flash-lite 404, found
    /// 2026-09-01, is the reason this exists: nobody knew until a real task
    /// failed). Default is an empty set ("nothing to check against") — local
    /// providers (Ollama/MLX) override this with nothing since they only
    /// ever list what's actually installed, immune to this failure class.
    func fetchModelIDs() async throws -> Set<String>
}

extension LLMProvider {
    func fetchModelIDs() async throws -> Set<String> { [] }

    func completeStream(
        systemPrompt: String,
        userText: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await complete(systemPrompt: systemPrompt, userText: userText, model: model)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum LLMError: LocalizedError {
    case noProviderConfigured
    case noAPIKey(provider: String)
    case httpError(status: Int, body: String)
    case invalidResponse
    case truncated
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No AI provider is configured."
        case .noAPIKey(let provider):
            return "No API key saved for \(provider). Add one in Settings → Providers."
        case .httpError(let status, let body):
            return "\(provider(forStatus: status)) (HTTP \(status)): \(body.prefix(240))"
        case .invalidResponse:
            return "Could not parse the AI response."
        case .truncated:
            return "The AI response was cut off (output length limit reached). Try a shorter text."
        case .cancelled:
            return "Cancelled."
        }
    }

    private func provider(forStatus status: Int) -> String {
        switch status {
        case 401, 403: return "API key invalid or unauthorized"
        case 429: return "Rate limit reached"
        case 500..<600: return "Provider server error"
        default: return "Network error"
        }
    }
}

// MARK: - OpenAI-compatible provider protocol

/// A provider that speaks the OpenAI `/chat/completions` schema. Conforming
/// types declare only their identity + endpoint; `complete`/`completeStream`
/// come from the default implementation below, so the five interchangeable
/// hosted providers (Kimi, Nebius, Groq, Scaleway, Mistral) carry no request
/// glue. Override `temperature(for:)` for per-model tuning — OpenAI omits it
/// for its reasoning family.
protocol OpenAICompatibleProvider: LLMProvider {
    var endpoint: URL { get }
    /// Temperature for a given model. Default 0.3; return `nil` to omit the
    /// field (reasoning models reject a custom temperature).
    func temperature(for model: String) -> Double?
}

/// Shared `GET .../models` response shape for every OpenAI-compatible
/// provider. File-scope, not nested in the protocol extension method below —
/// Swift rejects a type declared inside a protocol-extension function body.
struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

extension OpenAICompatibleProvider {
    func temperature(for model: String) -> Double? { 0.3 }

    /// Every OpenAI-compatible provider Tippi uses (OpenAI, Mistral, Scaleway,
    /// Groq, Kimi, Nebius, OpenRouter) also serves `GET .../models` one path
    /// segment up from `.../chat/completions`, in the same `{"data":[{"id":…}]}`
    /// shape as the request body — that's the whole OpenAI-compatibility
    /// convention these providers opted into. One implementation covers all
    /// seven instead of one per provider.
    func fetchModelIDs() async throws -> Set<String> {
        let apiKey = try await keychainAPIKey(id: id, displayName: displayName)
        let modelsURL = endpoint.deletingLastPathComponent().appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return Set(decoded.data.map(\.id))
    }

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        let apiKey = try await keychainAPIKey(id: id, displayName: displayName)
        let modelName = model.isEmpty ? defaultModel : model
        return try await openAIChatComplete(
            endpoint: endpoint,
            apiKey: apiKey,
            model: modelName,
            systemPrompt: systemPrompt,
            userText: userText,
            temperature: temperature(for: modelName)
        )
    }

    func completeStream(systemPrompt: String, userText: String, model: String) -> AsyncThrowingStream<String, Error> {
        let modelName = model.isEmpty ? defaultModel : model
        return openAIProviderStream(
            id: id, displayName: displayName, endpoint: endpoint,
            model: modelName,
            systemPrompt: systemPrompt, userText: userText,
            temperature: temperature(for: modelName)
        )
    }
}

// MARK: - Shared helpers for OpenAI-compatible providers

/// Fetches the Keychain API key for a provider, throwing `.noAPIKey` when
/// missing/empty. Keychain access is MainActor-bound.
func keychainAPIKey(id: String, displayName: String) async throws -> String {
    let key: String? = await MainActor.run { try? KeychainStore.getAPIKey(for: id) }
    guard let key, !key.isEmpty else { throw LLMError.noAPIKey(provider: displayName) }
    return key
}

/// One request/response path for every OpenAI-compatible `/chat/completions`
/// endpoint (OpenAI, Mistral, Scaleway, Groq). Centralises the timeout, the
/// truncation guard (`finish_reason == "length"` → `.truncated`, never insert a
/// cut-off rewrite), and JSON shaping so each provider only declares its
/// identity + endpoint. Anthropic, Gemini and Ollama keep bespoke paths
/// (different schemas).
func openAIChatComplete(
    endpoint: URL,
    apiKey: String,
    model: String,
    systemPrompt: String,
    userText: String,
    temperature: Double?,
    timeout: TimeInterval = 60
) async throws -> String {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    struct Message: Encodable { let role: String; let content: String }
    struct Body: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        enum CodingKeys: String, CodingKey { case model, messages, temperature }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(messages, forKey: .messages)
            // Reasoning models reject a custom temperature — omit when nil.
            if let temperature { try c.encode(temperature, forKey: .temperature) }
        }
    }
    let body = Body(
        model: model,
        messages: [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: userText)
        ],
        temperature: temperature
    )
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
        let text = String(data: data, encoding: .utf8) ?? ""
        throw LLMError.httpError(status: http.statusCode, body: text)
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            // content is optional: OpenAI-compatible endpoints return
            // `content: null` on content-filter refusals / empty output. Modeling
            // it as non-optional would surface a raw DecodingError to the user
            // instead of a clean LLMError. Matches the streaming decoder.
            struct Msg: Decodable { let content: String? }
            let message: Msg
            let finish_reason: String?
        }
        let choices: [Choice]
    }
    let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
    guard let choice = decoded.choices.first else { throw LLMError.invalidResponse }
    // A truncated rewrite must never be inserted — it would silently destroy
    // the tail of the user's text.
    guard choice.finish_reason != "length" else { throw LLMError.truncated }
    guard let content = choice.message.content else { throw LLMError.invalidResponse }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Provider-level streaming wrapper for OpenAI-compatible providers: fetches
/// the Keychain key, then forwards `openAIChatStream` deltas. Keeps each
/// provider's `completeStream` override to a single call.
func openAIProviderStream(
    id: String,
    displayName: String,
    endpoint: URL,
    model: String,
    systemPrompt: String,
    userText: String,
    temperature: Double?
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let apiKey = try await keychainAPIKey(id: id, displayName: displayName)
                for try await delta in openAIChatStream(
                    endpoint: endpoint, apiKey: apiKey, model: model,
                    systemPrompt: systemPrompt, userText: userText, temperature: temperature
                ) {
                    continuation.yield(delta)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Streaming sibling of `openAIChatComplete`. Consumes the server-sent-event
/// response (`data: {json}` lines) and yields `delta.content` fragments as they
/// arrive. Throws `.truncated` if the stream ends on `finish_reason == "length"`.
func openAIChatStream(
    endpoint: URL,
    apiKey: String,
    model: String,
    systemPrompt: String,
    userText: String,
    temperature: Double?,
    timeout: TimeInterval = 60
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = timeout
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                struct Message: Encodable { let role: String; let content: String }
                struct Body: Encodable {
                    let model: String
                    let messages: [Message]
                    let temperature: Double?
                    let stream: Bool
                    enum CodingKeys: String, CodingKey { case model, messages, temperature, stream }
                    func encode(to encoder: Encoder) throws {
                        var c = encoder.container(keyedBy: CodingKeys.self)
                        try c.encode(model, forKey: .model)
                        try c.encode(messages, forKey: .messages)
                        try c.encode(stream, forKey: .stream)
                        if let temperature { try c.encode(temperature, forKey: .temperature) }
                    }
                }
                let body = Body(
                    model: model,
                    messages: [
                        Message(role: "system", content: systemPrompt),
                        Message(role: "user", content: userText)
                    ],
                    temperature: temperature,
                    stream: true
                )
                request.httpBody = try JSONEncoder().encode(body)

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else {
                    var errBody = ""
                    for try await line in bytes.lines { errBody += line }
                    throw LLMError.httpError(status: http.statusCode, body: errBody)
                }

                struct Chunk: Decodable {
                    struct Choice: Decodable {
                        struct Delta: Decodable { let content: String? }
                        let delta: Delta
                        let finish_reason: String?
                    }
                    let choices: [Choice]
                }

                var truncated = false
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
                          let choice = chunk.choices.first else { continue }
                    if let delta = choice.delta.content, !delta.isEmpty {
                        continuation.yield(delta)
                    }
                    if choice.finish_reason == "length" { truncated = true }
                }
                if truncated { throw LLMError.truncated }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
