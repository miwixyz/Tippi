import Foundation

/// Request body of `mlx_lm.server`'s OpenAI-compatible chat endpoint. Shared by
/// `complete` and `prime`: the prompt cache only helps if both render the system
/// prompt identically, so they must not drift apart.
private struct Message: Encodable { let role: String; let content: String }
private struct ChatTemplateKwargs: Encodable { let enable_thinking: Bool }
private struct Body: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let max_tokens: Int
    let temperature: Double
    let chat_template_kwargs: ChatTemplateKwargs
}

struct MLXProvider: LLMProvider {
    let id           = "mlx"
    let displayName  = "MLX (local)"
    let defaultModel = "mlx-community/gemma-4-e2b-it-4bit"
    let requiresAPIKey = false

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userText: userText, model: model, temperature: nil)
    }

    func complete(systemPrompt: String, userText: String, model: String,
                  temperature hint: Double?) async throws -> String {
        // Ensure server is running (starts it if needed)
        let port = try await MLXServerManager.shared.start()
        let url  = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90  // startup is handled separately; keep running requests bounded
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // enable_thinking=false suppresses the chain-of-thought preamble of
        // thinking models so they return usable text in `content` instead of a
        // "Thinking Process:…" monologue in `reasoning`.
        //
        // This kwarg is the single thing standing between a curated preset and
        // a broken polish, so it constrains which models may be offered at all
        // (see `mlxPresets`): a model is only usable here if its Jinja chat
        // template either ignores the kwarg or gates thinking on it. Checked
        // 2026-09-15 by reading the actual `chat_template.jinja` of each
        // preset, not by assuming:
        //   - Qwen 3.5 (2B/4B/9B): gate on `enable_thinking`, suppressed. ✓
        //   - Gemma 4 E2B: also a thinking model now — unlike Gemma 3 — but
        //     gates the `<|think|>` token on `enable_thinking` being *defined
        //     and truthy*, so `false` suppresses it. Note its template opens the
        //     system turn for `tools` or a system-role first message too; that
        //     branch only renders the system prompt and does not re-enable
        //     thinking. ✓
        // An earlier version of this comment claimed Gemma simply ignores the
        // kwarg. That was true of Gemma 3 and is no longer true — right
        // behaviour, stale reason, which is the kind of note that gets trusted
        // later without rechecking.
        //
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
                Message(role: "user", content: userText)
            ],
            stream: false,
            max_tokens: maxTokens(for: userText),
            temperature: hint ?? 0.3,
            chat_template_kwargs: ChatTemplateKwargs(enable_thinking: false)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(status: http.statusCode, body: text)
        }
        // A successful completion proves the weights are loaded — self-heal the
        // menubar warm flag in case the background warm-up probe failed
        // transiently and left the badge stuck on "warming".
        await MainActor.run { MLXServerManager.shared.markWarm() }

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
        // Use `content` only. Thinking models also expose `reasoning` (their
        // internal chain-of-thought) — inserting that as the result would dump
        // "Let me think…" scratch text into the user's document, so treat an
        // empty content as an unusable response instead.
        let text = (first.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.invalidResponse }
        return text
    }

    /// Primes the server for an upcoming request with `systemPrompt`: one
    /// throwaway completion (`max_tokens` 1) with exactly that system prompt.
    /// `mlx_lm.server` keeps the prompt cache of its last request, so the real
    /// request afterwards only has to prefill the user text; the same call also
    /// pages the weights back in after macOS swapped them out during a long idle
    /// period. Fired when dictation starts, so the cost lands while the user is
    /// still speaking.
    ///
    /// Measured 2026-10-27 (Mac mini, gemma-4-e4b-it-4bit, dictation prompt):
    /// prime 3.1 s with a cold prefix, the real request afterwards 0.59 s with
    /// 606 of 624 prompt tokens cached. Without it, the first dictation polish
    /// after ~2 h idle took 20.6 s, all of it after recording had ended.
    /// `MLXServerManager.start()` returns immediately for a running server, so
    /// it never covered that case. Best-effort: all errors are ignored.
    static func prime(systemPrompt: String) async {
        guard let port = try? await MLXServerManager.shared.start(),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let resolvedModel = await MainActor.run { MLXServerManager.activeModel }
        let body = Body(
            model: resolvedModel,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: ".")
            ],
            stream: false,
            max_tokens: 1,
            temperature: 0,
            chat_template_kwargs: ChatTemplateKwargs(enable_thinking: false)
        )
        guard let data = try? JSONEncoder().encode(body) else { return }
        request.httpBody = data
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return }
        await MainActor.run { MLXServerManager.shared.markWarm() }
    }

    private func maxTokens(for userText: String) -> Int {
        // Most Tippi operations rewrite or summarize; a capped dynamic budget
        // keeps local models from drifting into slow, overly long completions.
        let approximateInputTokens = max(1, userText.count / 4)
        return min(2048, max(256, approximateInputTokens * 2))
    }
}
