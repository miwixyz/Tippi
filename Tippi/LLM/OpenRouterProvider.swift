import Foundation

/// OpenRouter — unified OpenAI-compatible gateway to 300+ models across every
/// major vendor (OpenAI, Anthropic, Google, Meta, Mistral, xAI, DeepSeek, …)
/// behind a single API key. Pass-through pricing (no markup up to 1M
/// requests/month, 5% beyond that) — verified 2026-09-01, not assumed.
///
/// Rationale for adding this as an 11th provider rather than a replacement
/// for the existing 8 cloud providers: it doesn't remove the "hardcoded
/// model ID can go stale" problem (OpenRouter's own IDs still track each
/// vendor's naming and can be retired the same way gemini-2.5-flash-lite
/// was) — its value for Tippi is one key instead of many, and reach into
/// models Tippi has no native integration for.
struct OpenRouterProvider: OpenAICompatibleProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    /// openai/gpt-4o-mini — cheap, fast, non-reasoning, matches Tippi's own
    /// native OpenAI default so behavior is comparable either way.
    let defaultModel = "openai/gpt-4o-mini"
    let requiresAPIKey = true

    let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
}
