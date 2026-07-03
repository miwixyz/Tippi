import Foundation

/// Nebius AI Studio — OpenAI-compatible API with 100 % EU data residency
/// (Amsterdam). DSGVO-compliant alternative to Groq for latency-sensitive
/// European use cases. Hosts open-weight models (Llama 3.x, Qwen, DeepSeek)
/// on European infrastructure.
///
/// Pricing (2026-07): ~$0.10–0.30 per 1M tokens depending on model.
/// EU invoicing available.
///
/// API keys: studio.nebius.ai
struct NebiusProvider: OpenAICompatibleProvider {
    let id = "nebius"
    let displayName = "Nebius (EU)"
    /// Llama 3.3 70B — best quality/speed balance in EU. Nebius renamed this
    /// model (dropped "Meta-" prefix and "-fast" suffix) some time after
    /// v1.14.0 shipped; verified live against /v1/models on 2026-07-03 —
    /// the old ID 404s.
    let defaultModel = "meta-llama/Llama-3.3-70B-Instruct"
    let requiresAPIKey = true

    let endpoint = URL(string: "https://api.studio.nebius.ai/v1/chat/completions")!
}
