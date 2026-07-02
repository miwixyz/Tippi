import Foundation

/// Curated lists of "current and suitable" model IDs per provider, so the
/// model picker in Settings only offers models that
///   1. exist today (deprecated/sunset IDs removed),
///   2. work for Tippi's "fix this short text, return only the result" use
///      case (no o1/o3 raw-reasoning models that swallow tokens before
///      output, no image-only models).
///
/// Each preset carries a hint flag (`isFastest`, `isReasoning`) so the
/// dictation-polish UI can default to the fastest non-reasoning option.
///
/// Maintained manually — provider model catalogues change every few weeks.
/// Last update: 2026-07-02 — added Kimi (Moonshot) + Nebius (EU).
enum ProviderModelPresets {

    struct Preset: Identifiable, Hashable {
        let id: String        // model ID sent to the API
        let label: String     // human-readable label for the picker
        let isFastest: Bool   // true → recommended for polish/latency-sensitive use
        let isReasoning: Bool // true → introduces thinking-token latency, avoid for polish
    }

    static func presets(for providerID: String) -> [Preset] {
        switch providerID {
        case "openai":     return openAI
        case "anthropic":  return anthropic
        case "gemini":     return gemini
        case "mistral":    return mistral
        case "scaleway":   return scaleway
        case "groq":       return groq
        case "kimi":       return kimi
        case "nebius":     return nebius
        default:           return []   // Ollama / MLX use their own pickers
        }
    }

    // MARK: - OpenAI (current 2026)
    //
    // Includes the gpt-5 reasoning family (premium quality, slower) and the
    // gpt-4o family (fast, non-reasoning). gpt-3.5-turbo and gpt-4 base
    // models are deliberately omitted — superseded by gpt-4o-mini at lower
    // price and higher quality.
    static let openAI: [Preset] = [
        Preset(id: "gpt-4o-mini",  label: "gpt-4o-mini — fast, cheap, non-reasoning ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "gpt-4o",       label: "gpt-4o — fast, non-reasoning",                isFastest: false, isReasoning: false),
        Preset(id: "gpt-5-nano",   label: "gpt-5-nano — small reasoning",                isFastest: false, isReasoning: true),
        Preset(id: "gpt-5-mini",   label: "gpt-5-mini — balanced reasoning",             isFastest: false, isReasoning: true),
        Preset(id: "gpt-5",        label: "gpt-5 — premium reasoning",                   isFastest: false, isReasoning: true),
    ]

    // MARK: - Anthropic (current 2026)
    static let anthropic: [Preset] = [
        Preset(id: "claude-haiku-4-5",  label: "Claude Haiku 4.5 — fastest ⭐",   isFastest: true,  isReasoning: false),
        Preset(id: "claude-sonnet-4-5", label: "Claude Sonnet 4.5 — balanced",   isFastest: false, isReasoning: false),
        Preset(id: "claude-opus-4-5",   label: "Claude Opus 4.5 — premium",      isFastest: false, isReasoning: false),
    ]

    // MARK: - Gemini (current 2026)
    static let gemini: [Preset] = [
        Preset(id: "gemini-2.5-flash-lite", label: "Gemini 2.5 Flash Lite — fastest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "gemini-2.5-flash",      label: "Gemini 2.5 Flash — fast",            isFastest: false, isReasoning: false),
        Preset(id: "gemini-2.5-pro",        label: "Gemini 2.5 Pro — premium",           isFastest: false, isReasoning: false),
    ]

    // MARK: - Mistral La Plateforme (EU/FR hosting, current 2026)
    //
    // Mistral hosts in Paris → DSGVO-compliant out of the box. Mistral
    // models excel at German/French nuance because they're trained with
    // European languages as a first-class concern.
    static let mistral: [Preset] = [
        Preset(id: "mistral-small-latest",  label: "Mistral Small — EU, fast, great German ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "mistral-medium-latest", label: "Mistral Medium — EU, premium German",       isFastest: false, isReasoning: false),
        Preset(id: "mistral-large-latest",  label: "Mistral Large — EU, top quality",           isFastest: false, isReasoning: false),
    ]

    // MARK: - Scaleway Generative APIs (EU/FR hosting, current 2026)
    //
    // Paris-hosted Llama 3.x / Mistral on Scaleway infrastructure. Sub-
    // second response for the 8B model, ~1 s for the 70B. Combines Groq-
    // class speed with EU data residency.
    static let scaleway: [Preset] = [
        Preset(id: "llama-3.1-8b-instruct",   label: "Llama 3.1 8B — EU, fastest ⭐",                  isFastest: true,  isReasoning: false),
        Preset(id: "llama-3.3-70b-instruct",  label: "Llama 3.3 70B — EU, premium quality",           isFastest: false, isReasoning: false),
        Preset(id: "mistral-nemo-instruct-2407", label: "Mistral Nemo 12B — EU, very good German",    isFastest: false, isReasoning: false),
        Preset(id: "qwen2.5-coder-32b-instruct", label: "Qwen 2.5 Coder 32B — EU, code-focused",      isFastest: false, isReasoning: false),
    ]

    // MARK: - Groq (LPU-accelerated, OpenAI-compatible)
    //
    // 8B-Instant is the fastest hosted model anywhere (~800 tok/s) — perfect
    // for dictation polish. 70B-Versatile is still sub-second on Groq and
    // gives noticeably better quality for German/long-form smoothing.
    static let groq: [Preset] = [
        Preset(id: "llama-3.1-8b-instant",      label: "Llama 3.1 8B Instant — ~800 tok/s ⭐",         isFastest: true,  isReasoning: false),
        Preset(id: "llama-3.3-70b-versatile",   label: "Llama 3.3 70B Versatile — ~270 tok/s, premium", isFastest: false, isReasoning: false),
        Preset(id: "openai/gpt-oss-20b",        label: "GPT-OSS 20B — OpenAI open weights",             isFastest: false, isReasoning: false),
    ]

    // MARK: - Kimi / Moonshot AI (global, OpenAI-compatible, 2026-07)
    //
    // Kimi K2 is a 1T-MoE open-weight model leading SWE-Bench Pro (58.6).
    // Very cheap at $0.95/$4.00 per 1M tokens (direct). 256K context.
    // moonshot-v1-* are the older instruction models — still useful for
    // short-text tasks like dictation polish due to low latency.
    static let kimi: [Preset] = [
        Preset(id: "kimi-k2",              label: "Kimi K2 — flagship, SWE-Bench #1 ⭐",       isFastest: false, isReasoning: false),
        Preset(id: "moonshot-v1-8k",       label: "Moonshot v1 8K — fast, short context",       isFastest: true,  isReasoning: false),
        Preset(id: "moonshot-v1-32k",      label: "Moonshot v1 32K — balanced",                 isFastest: false, isReasoning: false),
        Preset(id: "moonshot-v1-128k",     label: "Moonshot v1 128K — long context",            isFastest: false, isReasoning: false),
    ]

    // MARK: - Nebius AI Studio (EU/Amsterdam, OpenAI-compatible, 2026-07)
    //
    // 100 % EU data residency (Amsterdam). DSGVO-compliant. Very competitive
    // pricing (~$0.10–0.30 / 1M tokens). Hosts Llama 3.x, Qwen, DeepSeek.
    // "-fast" variants use tensor parallelism for lower latency.
    static let nebius: [Preset] = [
        Preset(id: "meta-llama/Meta-Llama-3.1-8B-Instruct-fast",  label: "Llama 3.1 8B — EU, fastest ⭐",        isFastest: true,  isReasoning: false),
        Preset(id: "meta-llama/Meta-Llama-3.3-70B-Instruct-fast", label: "Llama 3.3 70B — EU, premium quality", isFastest: false, isReasoning: false),
        Preset(id: "Qwen/Qwen3-235B-A22B-fast",                   label: "Qwen3 235B — EU, top quality",        isFastest: false, isReasoning: false),
        Preset(id: "deepseek-ai/DeepSeek-V3",                     label: "DeepSeek V3 — EU, strong coding",     isFastest: false, isReasoning: false),
    ]

    /// Default model for dictation polish on a given provider — picks the
    /// preset marked `isFastest` and not `isReasoning`. Returns nil if the
    /// provider has no curated presets (Ollama/MLX/unknown).
    static func defaultPolishModel(for providerID: String) -> String? {
        presets(for: providerID).first(where: { $0.isFastest && !$0.isReasoning })?.id
    }
}
