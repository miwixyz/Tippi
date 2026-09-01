import Foundation

/// Per-prompt provider/model override, independent of the global default
/// provider (Settings → Providers). Empty = use the global default via
/// `LLMRouter.effectivePreferredProviderID()`.
///
/// Generalizes the mechanism `DictationSettings.postProcessProviderOverride`
/// already uses for the one dictation-polish step to every prompt (currently
/// wired for built-in prompts, keyed by `DemoPrompt.id`). Rationale: a small
/// local model (e.g. MLX Qwen3.5 2B) can be the right default for short
/// dictation polish but returns a long, fact-dense business email completely
/// unchanged when asked to run "Improve" on it — real, reproduced behaviour,
/// not a prompt-wording issue. Rather than force everyone to a bigger/cloud
/// model globally, a single prompt can be pinned to a stronger provider.
@MainActor
enum PromptProviderOverride {
    static func providerID(for promptID: String) -> String {
        UserDefaults.standard.string(forKey: key(promptID, "provider")) ?? ""
    }

    static func setProviderID(_ value: String, for promptID: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(promptID, "provider"))
        } else {
            UserDefaults.standard.set(value, forKey: key(promptID, "provider"))
        }
    }

    static func modelOverride(for promptID: String) -> String {
        UserDefaults.standard.string(forKey: key(promptID, "model")) ?? ""
    }

    static func setModelOverride(_ value: String, for promptID: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(promptID, "model"))
        } else {
            UserDefaults.standard.set(value, forKey: key(promptID, "model"))
        }
    }

    private static func key(_ promptID: String, _ suffix: String) -> String {
        "prompt.providerOverride.\(promptID).\(suffix)"
    }
}
