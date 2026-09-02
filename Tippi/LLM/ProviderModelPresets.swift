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
        case "openrouter": return openRouter
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

    // MARK: - Gemini (updated 2026-09-01)
    //
    // The 2.5 generation started returning HTTP 404 "no longer available to
    // new users" ahead of its official Oct 2026 shutdown date — reproduced
    // live via a real Tippi error on gemini-2.5-flash-lite, which the error
    // body itself pointed at gemini-3.5-flash-lite as the replacement.
    // gemini-3.5-flash confirmed via ai.google.dev as the flash-tier GA
    // successor. gemini-2.5-pro's exact GA 3.x replacement could NOT be
    // confirmed with confidence (docs only surfaced a "-preview"-suffixed
    // pro ID, too unstable to hardcode) — left on 2.5-pro, flagged here so
    // it isn't silently trusted if it starts 404ing too.
    static let gemini: [Preset] = [
        Preset(id: "gemini-3.5-flash-lite", label: "Gemini 3.5 Flash Lite — fastest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "gemini-3.5-flash",      label: "Gemini 3.5 Flash — fast",            isFastest: false, isReasoning: false),
        Preset(id: "gemini-2.5-pro",        label: "Gemini 2.5 Pro — premium ⚠️ unverified, may 404",  isFastest: false, isReasoning: false),
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

    // MARK: - Nebius AI Studio (EU/Amsterdam, OpenAI-compatible)
    //
    // 100 % EU data residency (Amsterdam). DSGVO-compliant. Very competitive
    // pricing (~$0.10–0.30 / 1M tokens). Hosts Llama, Qwen, DeepSeek.
    //
    // ⚠️ Model IDs verified against the live /v1/models catalog on 2026-07-24.
    // Nebius removed the earlier "-fast" variants (they now 404) — do NOT
    // reintroduce `*-Instruct-fast` ids. "fastest" is a MoE model (Qwen3-30B-A3B,
    // ~3B active params) which is fast without a separate `-fast` sku.
    static let nebius: [Preset] = [
        Preset(id: "Qwen/Qwen3-30B-A3B-Instruct-2507",     label: "Qwen3 30B A3B — EU, fastest ⭐",      isFastest: true,  isReasoning: false),
        Preset(id: "meta-llama/Llama-3.3-70B-Instruct",    label: "Llama 3.3 70B — EU, premium quality", isFastest: false, isReasoning: false),
        Preset(id: "Qwen/Qwen3-235B-A22B-Instruct-2507",   label: "Qwen3 235B — EU, top quality",        isFastest: false, isReasoning: false),
        Preset(id: "deepseek-ai/DeepSeek-V4-Pro",          label: "DeepSeek V4 — EU, strong coding",     isFastest: false, isReasoning: false),
    ]

    // MARK: - OpenRouter (unified gateway, current 2026)
    //
    // Vendor-prefixed IDs (openrouter routes "vendor/model" to that vendor's
    // backend). Curated to the same three vendors Tippi already has native
    // integrations for, on IDs already verified elsewhere in this file/session
    // — not a reason to trust OpenRouter's full 300+ catalogue blindly, just a
    // safe starting trio. OpenRouter aliasing a vendor rename doesn't make
    // Tippi immune to the "hardcoded id goes stale" problem (see gemini-2.5
    // incident, 2026-09-01) — it inherits whatever the upstream vendor does.
    static let openRouter: [Preset] = [
        Preset(id: "openai/gpt-4o-mini",           label: "GPT-4o mini (via OpenRouter) — fastest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "anthropic/claude-haiku-4-5",   label: "Claude Haiku 4.5 (via OpenRouter) — balanced", isFastest: false, isReasoning: false),
        Preset(id: "google/gemini-3.5-flash",      label: "Gemini 3.5 Flash (via OpenRouter) — balanced", isFastest: false, isReasoning: false),
    ]

    /// Default model for dictation polish on a given provider — picks the
    /// preset marked `isFastest` and not `isReasoning`. Returns nil if the
    /// provider has no curated presets (Ollama/MLX/unknown).
    static func defaultPolishModel(for providerID: String) -> String? {
        presets(for: providerID).first(where: { $0.isFastest && !$0.isReasoning })?.id
    }

    /// A model id a provider has retired. Any persisted selection pointing at
    /// `deadID` — the provider's own default, the dictation-polish override,
    /// or a per-built-in-prompt override — silently keeps 404ing forever
    /// after an app update unless rewritten, because a saved UserDefaults
    /// value always wins over a new static default/preset. Updating
    /// `openAI`/`gemini`/etc. above only changes what a *fresh* pick sees.
    struct RetiredModel {
        let providerID: String
        let deadID: String
        let replacementID: String
    }

    /// Every known provider model retirement discovered so far. Add a line
    /// here whenever a provider pulls a model id out from under existing
    /// users — this is the second time in 2026 (Nebius mid-2026, Gemini
    /// 2.5→3.5 on 2026-09-01) and won't be the last; providers routinely
    /// retire ids faster than this file gets manually updated.
    static let retiredModels: [RetiredModel] = [
        .init(providerID: "nebius", deadID: "meta-llama/Meta-Llama-3.1-8B-Instruct-fast",  replacementID: "Qwen/Qwen3-30B-A3B-Instruct-2507"),
        .init(providerID: "nebius", deadID: "meta-llama/Meta-Llama-3.3-70B-Instruct-fast", replacementID: "meta-llama/Llama-3.3-70B-Instruct"),
        .init(providerID: "nebius", deadID: "Qwen/Qwen3-235B-A22B-fast",                   replacementID: "Qwen/Qwen3-235B-A22B-Instruct-2507"),
        .init(providerID: "nebius", deadID: "deepseek-ai/DeepSeek-V3",                     replacementID: "deepseek-ai/DeepSeek-V4-Pro"),
        // Google retired the 2.5 generation ahead of its official Oct 2026
        // shutdown — reproduced live via a real gemini-2.5-flash-lite 404,
        // see GeminiProvider.swift / the `gemini` presets above.
        .init(providerID: "gemini", deadID: "gemini-2.5-flash-lite", replacementID: "gemini-3.5-flash-lite"),
        .init(providerID: "gemini", deadID: "gemini-2.5-flash",      replacementID: "gemini-3.5-flash"),
    ]

    /// Rewrites every persisted model selection that points at a known-dead
    /// id: the provider's own `defaultModel.<id>`, the dictation-polish
    /// override, and every built-in prompt's per-prompt provider override
    /// (`prompt.providerOverride.<promptID>.model`). Idempotent — only
    /// touches values that exactly match a `retiredModels` entry, so it's a
    /// silent no-op on every launch after the first for a given remap.
    /// Call once at app launch, before anything reads a persisted model id.
    @MainActor
    static func migrateRetiredModels(defaults: UserDefaults = .standard) {
        let promptIDs = DemoPrompt.builtIn.map(\.id)
        for retired in retiredModels {
            var keysToCheck = [
                "defaultModel.\(retired.providerID)",
                "dictation.postProcess.modelOverride",
            ]
            keysToCheck += promptIDs.map { "prompt.providerOverride.\($0).model" }
            for key in keysToCheck {
                guard defaults.string(forKey: key) == retired.deadID else { continue }
                defaults.set(retired.replacementID, forKey: key)
                NSLog("Tippi: migrated retired \(retired.providerID) model '\(retired.deadID)' → '\(retired.replacementID)' (key: \(key))")
            }
        }
    }
}
