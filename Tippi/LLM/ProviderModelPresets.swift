// swiftlint:disable comma
// Die Preset-Tabellen sind spaltenweise ausgerichtet, damit isFastest/isReasoning
// zeilenweise vergleichbar bleiben — die comma-Regel würde das plattmachen.

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
/// Partial audit 2026-09-25: Anthropic (Opus 5.5) and OpenRouter (live
/// `/api/v1/models` + per-model `/endpoints`), see the notes on each list.
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
    //
    // 2026-09-25: gpt-6-luna ($0.10/$0.50) and gpt-6-sol ($2/$10) replace their
    // 5.6 namesakes. Both are reasoning models but accept
    // `reasoning_effort: "none"`, which OpenAIProvider sends — so they run
    // without thinking tokens and count as non-reasoning here. There is no
    // gpt-6-terra; gpt-5.6-terra stays as the middle option. gpt-5.6-luna/-sol
    // are NOT retired (not on OpenAI's deprecations page), so stored picks of
    // them keep working and are deliberately not rewritten.
    static let openAI: [Preset] = [
        Preset(id: "gpt-6-luna",    label: "GPT-6 Luna — fastest, cheapest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "gpt-5.6-terra", label: "GPT-5.6 Terra — balanced",          isFastest: false, isReasoning: true),
        Preset(id: "gpt-6-sol",     label: "GPT-6 Sol — premium",               isFastest: false, isReasoning: false),
    ]

    // MARK: - Anthropic (verified against platform.claude.com, 2026-09-02; Opus 5.5 2026-09-25)
    //
    // Haiku 4.5 is still the fastest and cheapest of the lineup ($1/$5 per
    // MTok) and stays the ⭐ pick for short rewrites — but Anthropic lists its
    // retirement as "not sooner than October 15, 2026", so it is on borrowed
    // time and there is no Haiku 5 yet. Sonnet 5 is the fallback when it goes.
    // Sonnet 4.5 / Opus 4.5 were shipped here until now and are both legacy —
    // replaced by the 5 generation and migrated via `retiredModels`.
    // 2026-09-25: Opus 5.5 (`claude-opus-5-5`, $4/$20) replaces Opus 5 as the
    // premium preset — cheaper and faster. Opus 5 itself is NOT retired (not
    // before 2027-07-24), so stored `claude-opus-5` selections are left alone.
    // 2026-10-09: Haiku 5.5 (`claude-haiku-5-5`, from $0.10/$0.50, 07.10.2026) added as
    // an option, not yet the ⭐ default: measured against Haiku 4.5 on four real dictations
    // with the default polish prompt — same latency (1.0–1.7 s) with effort `low` + thinking
    // disabled (AnthropicProvider sends both), but it kept fillers ("also", "genau") and read
    // "punkt" as "Pünktlich". Opus 5.5 always thinks (adaptive) → isReasoning.
    static let anthropic: [Preset] = [
        Preset(id: "claude-haiku-4-5",  label: "Claude Haiku 4.5 — fastest, cheapest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "claude-haiku-5-5",  label: "Claude Haiku 5.5 — newest, cheaper",      isFastest: false, isReasoning: false),
        Preset(id: "claude-sonnet-5",   label: "Claude Sonnet 5 — balanced",              isFastest: false, isReasoning: false),
        Preset(id: "claude-opus-5-5",   label: "Claude Opus 5.5 — premium",               isFastest: false, isReasoning: true),
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

    // MARK: - OpenRouter (unified gateway, current 2026)
    //
    // Vendor-prefixed IDs (openrouter routes "vendor/model" to that vendor's
    // backend). Curated to the same three vendors Tippi already has native
    // integrations for, on IDs already verified elsewhere in this file/session
    // — not a reason to trust OpenRouter's full 300+ catalogue blindly, just a
    // safe starting trio. OpenRouter aliasing a vendor rename doesn't make
    // Tippi immune to the "hardcoded id goes stale" problem (see gemini-2.5
    // incident, 2026-09-01) — it inherits whatever the upstream vendor does.
    //
    // Checked live 2026-09-25 against /api/v1/models and each model's
    // /endpoints: OpenRouter's ids do NOT mirror the vendor's own spelling.
    // `google/gemini-flash-latest` returned 404 — the auto-updating alias is
    // `~google/gemini-flash-latest` (leading tilde). `anthropic/claude-haiku-4-5`
    // still resolved, but only as an alias of `anthropic/claude-haiku-4.5`
    // (dot); the catalogue lists the dotted form, so ModelAvailabilityChecker's
    // prefix match would flag the dashed one as outdated. Always copy ids from
    // OpenRouter's catalogue, never derive them from the vendor's id.
    static let openRouter: [Preset] = [
        Preset(id: "anthropic/claude-haiku-4.5",   label: "Claude Haiku 4.5 (via OpenRouter) — fastest ⭐", isFastest: true,  isReasoning: false),
        Preset(id: "anthropic/claude-haiku-5.5",   label: "Claude Haiku 5.5 (via OpenRouter) — newest",     isFastest: false, isReasoning: false),
        Preset(id: "openai/gpt-6-luna",            label: "GPT-6 Luna (via OpenRouter) — cheap",            isFastest: false, isReasoning: false),
        Preset(id: "~google/gemini-flash-latest",  label: "Gemini Flash latest (via OpenRouter)",           isFastest: false, isReasoning: false),
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
    /// users — this is the second time in 2026 (Nebius mid-2026 — provider since removed, Gemini
    /// 2.5→3.5 on 2026-09-01) and won't be the last; providers routinely
    /// retire ids faster than this file gets manually updated.
    static let retiredModels: [RetiredModel] = [
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
        // Targets moved to gpt-6 on 2026-09-25 (the 5.6 Luna/Sol are no longer
        // presets, and a target must be one — see ProviderModelPresetsTests).
        .init(providerID: "openai", deadID: "gpt-4o-mini", replacementID: "gpt-6-luna"),
        .init(providerID: "openai", deadID: "gpt-4o",      replacementID: "gpt-5.6-terra"),
        .init(providerID: "openai", deadID: "gpt-5-nano",  replacementID: "gpt-6-luna"),
        .init(providerID: "openai", deadID: "gpt-5-mini",  replacementID: "gpt-5.6-terra"),
        .init(providerID: "openai", deadID: "gpt-5",       replacementID: "gpt-6-sol"),

        // Anthropic's 4.5 Sonnet/Opus are legacy since the 5 generation.
        // Haiku 4.5 is deliberately NOT remapped — it's still the fastest and
        // cheapest model Anthropic sells and remains the right pick until its
        // announced retirement (not before 2026-10-15).
        .init(providerID: "anthropic", deadID: "claude-sonnet-4-5", replacementID: "claude-sonnet-5"),
        .init(providerID: "anthropic", deadID: "claude-opus-4-5",   replacementID: "claude-opus-5-5"),

        // OpenRouter passes vendor ids straight through, so it inherits every
        // upstream retirement above under its `vendor/` prefix.
        .init(providerID: "openrouter", deadID: "openai/gpt-4o-mini",      replacementID: "openai/gpt-6-luna"),
        .init(providerID: "openrouter", deadID: "google/gemini-3.5-flash", replacementID: "~google/gemini-flash-latest"),
        // 2026-09-25: Tippi's own presets used ids OpenRouter doesn't list —
        // one 404s, the other is only an alias (see the openRouter presets).
        .init(providerID: "openrouter", deadID: "google/gemini-flash-latest", replacementID: "~google/gemini-flash-latest"),
        .init(providerID: "openrouter", deadID: "anthropic/claude-haiku-4-5", replacementID: "anthropic/claude-haiku-4.5"),
    ]
    // swiftlint:enable comma

    /// Rewrites every persisted model selection that points at a known-dead
    /// id: the provider's own `defaultModel.<id>`, the dictation-polish
    /// override, and every prompt's per-prompt provider override
    /// (`prompt.providerOverride.<promptID>.model`) — built-in and custom
    /// (`custom-<uuid>`, see `CustomPrompt.demoID`). Custom prompts were
    /// missed until 2026-09-28, so their pinned dead model kept failing.
    /// Idempotent — only touches values that exactly match a `retiredModels`
    /// entry, so it's a silent no-op on every launch after the first for a
    /// given remap. Call once at app launch, before anything reads a
    /// persisted model id.
    @MainActor
    static func migrateRetiredModels(defaults: UserDefaults = .standard) {
        // Custom prompts decoded straight from `defaults`, not via
        // `CustomPromptStore`: that one writes a `.corrupt` backup on a
        // decoding error — a side effect a migration must not have.
        let customIDs = defaults.data(forKey: CustomPromptStore.storageKey)
            .flatMap { try? JSONDecoder().decode([CustomPrompt].self, from: $0) }?
            .map(\.demoID) ?? []
        let promptIDs = DemoPrompt.builtIn.map(\.id) + customIDs
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

    /// Providers removed from Tippi (2.24.0, 2026-10-09): Kimi, Scaleway, Groq and Nebius.
    /// Most of their preset models had been switched off by the providers themselves
    /// (Kimi: all four; Scaleway: three of four), and Michael wants them gone.
    static let removedProviderIDs: Set<String> = ["kimi", "scaleway", "groq", "nebius"]

    /// Clears every persisted choice that points at a removed provider — the default
    /// provider, the dictation-polish override and every prompt's provider override —
    /// together with the model picked for it. Afterwards the router falls back to the
    /// first provider with a key, exactly like a fresh install. Idempotent.
    @MainActor
    static func migrateRemovedProviders(defaults: UserDefaults = .standard) {
        func clear(_ providerKey: String, modelKey: String?) {
            guard let id = defaults.string(forKey: providerKey), removedProviderIDs.contains(id) else { return }
            defaults.removeObject(forKey: providerKey)
            if let modelKey { defaults.removeObject(forKey: modelKey) }
            NSLog("Tippi: removed provider '\(id)' cleared (key: \(providerKey))")
        }
        clear("defaultProvider", modelKey: nil)
        clear("dictation.postProcess.providerOverride", modelKey: "dictation.postProcess.modelOverride")
        let customIDs = defaults.data(forKey: CustomPromptStore.storageKey)
            .flatMap { try? JSONDecoder().decode([CustomPrompt].self, from: $0) }?
            .map(\.demoID) ?? []
        for promptID in DemoPrompt.builtIn.map(\.id) + customIDs {
            clear("prompt.providerOverride.\(promptID).provider", modelKey: "prompt.providerOverride.\(promptID).model")
        }
        for id in removedProviderIDs { defaults.removeObject(forKey: "defaultModel.\(id)") }
    }
}
