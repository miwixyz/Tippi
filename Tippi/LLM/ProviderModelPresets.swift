import Foundation

/// Curated lists of "current and suitable" model IDs per provider, so the
/// model picker in Settings only offers models that
///   1. exist today (deprecated/sunset IDs removed),
///   2. work for Tippi's "fix this short text, return only the result" use
///      case (no raw-reasoning models that swallow tokens before output,
///      no image-only models).
///
/// Each preset carries a hint flag (`isFastest`, `isReasoning`) so the
/// dictation-polish UI can default to the fastest non-reasoning option.
///
/// ## Keeping this current — three layers, in order of preference
///
/// A full audit on 2026-09-02 found stale ids at **four of nine** cloud
/// providers at once (OpenAI's whole gpt-4o/gpt-5 line gone, Groq's entire
/// Llama line deprecated, two Anthropic presets superseded, Gemini already
/// one generation behind a fix shipped a day earlier). Hand-maintenance
/// alone demonstrably does not keep up. So:
///
/// 1. **Prefer auto-updating aliases where a provider publishes them.**
///    Mistral (`mistral-small-latest`) and Gemini (`gemini-flash-latest`,
///    hot-swapped on every release) survive generation changes with no app
///    update at all — Mistral is the only provider that never broke here.
///    Use the alias unless there's a concrete reason to pin.
/// 2. **`retiredModels` migrates users off dead ids** (below). Updating a
///    preset alone does nothing for someone who already picked a model:
///    a stored UserDefaults value always wins over a new default.
/// 3. **`ModelAvailabilityChecker` flags what slipped through** by asking
///    each provider's live `/models` endpoint at launch. It's the safety
///    net, not the plan — it can only warn, never pick a good replacement.
///
/// Last full audit: 2026-09-02 (verified against each provider's own docs).
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

    // MARK: - OpenAI (verified against developers.openai.com, 2026-09-02)
    //
    // The whole gpt-4o and gpt-5 generation is gone from OpenAI's current
    // model list — the catalogue is now the gpt-5.6 trio. Every preset here
    // was replaced; the old ones (gpt-4o-mini, gpt-4o, gpt-5-nano/mini/gpt-5)
    // are in `retiredModels` so existing users get migrated rather than left
    // on an id that is no longer listed.
    //
    // Caveat worth knowing: all three current models support reasoning, so
    // there is no true "non-reasoning" option at OpenAI anymore. Luna is the
    // cheapest and fastest of the three and therefore the ⭐ pick for Tippi's
    // short-rewrite workload.
    static let openAI: [Preset] = [
        Preset(id: "gpt-5.6-luna",  label: "GPT-5.6 Luna — fastest, cheapest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "gpt-5.6-terra", label: "GPT-5.6 Terra — balanced",            isFastest: false, isReasoning: true),
        Preset(id: "gpt-5.6-sol",   label: "GPT-5.6 Sol — premium",               isFastest: false, isReasoning: true),
    ]

    // MARK: - Anthropic (verified against platform.claude.com, 2026-09-02)
    //
    // Haiku 4.5 is still the fastest and cheapest of the lineup ($1/$5 per
    // MTok) and stays the ⭐ pick for short rewrites — but Anthropic lists its
    // retirement as "not sooner than October 15, 2026", so it is on borrowed
    // time and there is no Haiku 5 yet. Sonnet 5 is the fallback when it goes.
    // Sonnet 4.5 / Opus 4.5 were shipped here until now and are both legacy —
    // replaced by the 5 generation and migrated via `retiredModels`.
    static let anthropic: [Preset] = [
        Preset(id: "claude-haiku-4-5",  label: "Claude Haiku 4.5 — fastest, cheapest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "claude-sonnet-5",   label: "Claude Sonnet 5 — balanced",              isFastest: false, isReasoning: false),
        Preset(id: "claude-opus-5",     label: "Claude Opus 5 — premium",                 isFastest: false, isReasoning: false),
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
    // Google publishes auto-updating aliases ("hot-swapped with every new
    // release") — `gemini-flash-lite-latest` / `gemini-flash-latest` keep
    // working across generation changes without an app update, which is
    // exactly the failure this file kept hitting. Prefer them over pinned
    // ids wherever a provider offers the convention (Mistral's `-latest`
    // aliases are the same idea and are why Mistral never broke here).
    // The pinned 3.7 entry stays available for anyone who wants a fixed
    // target; `gemini-2.5-pro` is dropped — the 2.5 generation is being
    // retired and no confirmed 3.x Pro GA id exists to replace it with.
    static let gemini: [Preset] = [
        Preset(id: "gemini-flash-lite-latest", label: "Gemini Flash Lite (latest) — fastest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "gemini-flash-latest",      label: "Gemini Flash (latest) — auto-updating",  isFastest: false, isReasoning: false),
        Preset(id: "gemini-3.7-flash",         label: "Gemini 3.7 Flash — pinned, most capable", isFastest: false, isReasoning: false),
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

    // MARK: - Groq (LPU-accelerated, verified 2026-09-02)
    //
    // Groq deprecated its whole Llama chat line on 2026-06-17, including both
    // models Tippi shipped: llama-3.1-8b-instant (the ⭐ dictation-polish pick)
    // and llama-3.3-70b-versatile (the default). Groq's own migration advice
    // names gpt-oss-20b and gpt-oss-120b / qwen3.6-27b as replacements, which
    // is what's here. Both dead ids are in `retiredModels`.
    static let groq: [Preset] = [
        Preset(id: "openai/gpt-oss-20b",   label: "GPT-OSS 20B — fastest ⭐",              isFastest: true,  isReasoning: false),
        Preset(id: "openai/gpt-oss-120b",  label: "GPT-OSS 120B — premium quality",        isFastest: false, isReasoning: false),
        Preset(id: "qwen/qwen3.6-27b",     label: "Qwen 3.6 27B — strong multilingual",    isFastest: false, isReasoning: false),
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
        Preset(id: "anthropic/claude-haiku-4-5",   label: "Claude Haiku 4.5 (via OpenRouter) — fastest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "openai/gpt-5.6-luna",          label: "GPT-5.6 Luna (via OpenRouter) — cheap",          isFastest: false, isReasoning: false),
        Preset(id: "google/gemini-flash-latest",   label: "Gemini Flash latest (via OpenRouter)",           isFastest: false, isReasoning: false),
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
        // see GeminiProvider.swift / the `gemini` presets above. Targets are
        // now the auto-updating aliases so this can't need a third round.
        .init(providerID: "gemini", deadID: "gemini-2.5-flash-lite", replacementID: "gemini-flash-lite-latest"),
        .init(providerID: "gemini", deadID: "gemini-2.5-flash",      replacementID: "gemini-flash-latest"),
        .init(providerID: "gemini", deadID: "gemini-3.5-flash-lite", replacementID: "gemini-flash-lite-latest"),
        .init(providerID: "gemini", deadID: "gemini-3.5-flash",      replacementID: "gemini-flash-latest"),
        .init(providerID: "gemini", deadID: "gemini-2.5-pro",        replacementID: "gemini-flash-latest"),

        // OpenAI's gpt-4o and gpt-5 generations are no longer in the current
        // model list (developers.openai.com, checked 2026-09-02); the whole
        // catalogue is the gpt-5.6 trio now. Luna is the cheapest/fastest and
        // the closest match to what these ids were chosen for.
        .init(providerID: "openai", deadID: "gpt-4o-mini", replacementID: "gpt-5.6-luna"),
        .init(providerID: "openai", deadID: "gpt-4o",      replacementID: "gpt-5.6-terra"),
        .init(providerID: "openai", deadID: "gpt-5-nano",  replacementID: "gpt-5.6-luna"),
        .init(providerID: "openai", deadID: "gpt-5-mini",  replacementID: "gpt-5.6-terra"),
        .init(providerID: "openai", deadID: "gpt-5",       replacementID: "gpt-5.6-sol"),

        // Anthropic's 4.5 Sonnet/Opus are legacy since the 5 generation.
        // Haiku 4.5 is deliberately NOT remapped — it's still the fastest and
        // cheapest model Anthropic sells and remains the right pick until its
        // announced retirement (not before 2026-10-15).
        .init(providerID: "anthropic", deadID: "claude-sonnet-4-5", replacementID: "claude-sonnet-5"),
        .init(providerID: "anthropic", deadID: "claude-opus-4-5",   replacementID: "claude-opus-5"),

        // Groq deprecated its entire Llama chat line on 2026-06-17. These two
        // were Tippi's default and its "fastest" pick — replacements are the
        // ones Groq's own migration notice names.
        .init(providerID: "groq", deadID: "llama-3.1-8b-instant",    replacementID: "openai/gpt-oss-20b"),
        .init(providerID: "groq", deadID: "llama-3.3-70b-versatile", replacementID: "openai/gpt-oss-120b"),

        // OpenRouter passes vendor ids straight through, so it inherits every
        // upstream retirement above under its `vendor/` prefix.
        .init(providerID: "openrouter", deadID: "openai/gpt-4o-mini",      replacementID: "openai/gpt-5.6-luna"),
        .init(providerID: "openrouter", deadID: "google/gemini-3.5-flash", replacementID: "google/gemini-flash-latest"),
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
