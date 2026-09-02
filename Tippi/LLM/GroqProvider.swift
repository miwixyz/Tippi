import Foundation

/// Groq Cloud — OpenAI-compatible chat completions endpoint backed by Groq's
/// LPU inference hardware. Hosted Llama / GPT-OSS models stream at 270–800
/// tokens/sec, making this the fastest hosted provider for short-text tasks
/// like dictation polishing (sub-second round-trip in practice).
struct GroqProvider: OpenAICompatibleProvider {
    let id = "groq"
    let displayName = "Groq"
    /// Llama 3.3 70B Versatile — strong quality at ~270 tok/s. The
    /// `llama-3.1-8b-instant` preset is faster (~800 tok/s) when latency
    /// matters more than quality.
    // Groq deprecated its whole Llama chat line on 2026-06-17. gpt-oss-20b
    // is the replacement Groq itself names for the fast tier, and keeps this
    // provider in its role as Tippi's low-latency option.
    let defaultModel = "openai/gpt-oss-20b"
    let requiresAPIKey = true

    let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
}
