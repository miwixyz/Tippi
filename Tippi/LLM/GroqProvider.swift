import Foundation

/// Groq Cloud — OpenAI-compatible chat completions endpoint backed by Groq's
/// LPU inference hardware. Hosted Llama / GPT-OSS models stream at 270–800
/// tokens/sec, making this the fastest hosted provider for short-text tasks
/// like dictation polishing (sub-second round-trip in practice).
struct GroqProvider: OpenAICompatibleProvider {
    let id = "groq"
    let displayName = "Groq"
    // Default = `openai/gpt-oss-20b`: the replacement Groq itself names for
    // its fast tier, keeping this provider in its role as Tippi's low-latency
    // option. Until 2026-06-17 this was Llama 3.3 70B Versatile; Groq
    // deprecated its whole Llama chat line on that date.
    let defaultModel = "openai/gpt-oss-20b"
    let requiresAPIKey = true

    let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
}
