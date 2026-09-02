import Foundation

/// Proactively checks whether each configured provider's currently-selected
/// model still exists on that provider's live catalogue, instead of only
/// finding out via a failed real task — the gemini-2.5-flash-lite incident,
/// 2026-09-01: the model had already been retired, but nothing told the user
/// until "Improve" on a real email came back HTTP 404.
///
/// Best-effort by design: a failed fetch (no key, network error, provider
/// has no live catalogue — see `LLMProvider.fetchModelCatalog()`'s `.unknown`
/// default for Ollama/MLX) is silently skipped, as is a catalogue that came
/// back paginated. This is a convenience warning shown in Settings, never a
/// blocker — checking must never break or slow down an actual transform, and
/// must never claim a working model is retired.
@MainActor
final class ModelAvailabilityChecker: ObservableObject {
    static let shared = ModelAvailabilityChecker()

    /// A configured model that the provider's live catalogue no longer lists,
    /// together with a replacement that was **verified against that same
    /// catalogue** — never a guess. `suggested` is nil when none of Tippi's
    /// curated presets for that provider are live either, in which case the
    /// user has to choose manually rather than be pushed at another dead id.
    struct StaleModel {
        let providerID: String
        let configured: String
        let suggested: String?
    }

    /// Provider ids whose configured model was NOT found in that provider's
    /// live catalogue on the last check. Empty until the first check
    /// completes, or if every check failed/was skipped.
    @Published private(set) var possiblyStale: Set<String> = []
    /// Details + verified replacement per stale provider, keyed by provider id.
    @Published private(set) var staleDetails: [String: StaleModel] = [:]
    @Published private(set) var lastCheckedAt: Date?

    private init() {}

    /// Switches a provider to the replacement found during the last check.
    ///
    /// Deliberately user-triggered rather than automatic. The retired-model
    /// migration (`ProviderModelPresets.retiredModels`) already auto-fixes the
    /// cases someone curated and verified; everything reaching here is a model
    /// Tippi only knows is *absent*, and swapping it silently would change
    /// price and output quality without asking. One click, with the target
    /// named, is the honest version of "and update it if needed".
    func applySuggestion(for providerID: String) {
        guard let detail = staleDetails[providerID], let suggested = detail.suggested else { return }
        UserDefaults.standard.set(suggested, forKey: "defaultModel.\(providerID)")
        NSLog("Tippi: switched \(providerID) from retired '\(detail.configured)' to '\(suggested)' on user request")
        possiblyStale.remove(providerID)
        staleDetails[providerID] = nil
    }

    /// Checks every provider that requires a key and has one configured.
    /// Runs all checks concurrently — with up to 11 providers, doing this
    /// serially would make launch-time checking noticeably slow for no
    /// benefit. Call from a background `Task`, not on the launch critical
    /// path (see `AppDelegate.applicationDidFinishLaunching`).
    func checkAllConfigured() async {
        let configured = LLMRouter.allProviders.filter {
            $0.requiresAPIKey && KeychainStore.hasAPIKey(for: $0.id)
        }
        guard !configured.isEmpty else { return }

        let results: [StaleModel?] = await withTaskGroup(of: StaleModel?.self) { group in
            for provider in configured {
                let presets = ProviderModelPresets.presets(for: provider.id).map(\.id)
                group.addTask {
                    let configuredModel = UserDefaults.standard.string(forKey: "defaultModel.\(provider.id)")
                        ?? provider.defaultModel
                    guard let catalog = try? await provider.fetchModelCatalog(),
                          catalog.isComplete,
                          !catalog.ids.isEmpty else {
                        // Fetch failed, provider has no live catalogue, or the
                        // list came back paginated/partial → treat as fine.
                        // Never warn on incomplete data: a truncated catalogue
                        // makes working models look retired, which is exactly
                        // how v1.21.0 falsely flagged claude-haiku-4-5.
                        return nil
                    }
                    guard !catalog.plausiblyServes(configuredModel) else { return nil }
                    // Only suggest a preset the SAME catalogue confirms is
                    // live — proposing another dead id would repeat the very
                    // failure this check exists to catch.
                    let suggested = presets.first { catalog.plausiblyServes($0) }
                    return StaleModel(
                        providerID: provider.id,
                        configured: configuredModel,
                        suggested: suggested
                    )
                }
            }
            var collected: [StaleModel?] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let found = results.compactMap { $0 }
        for entry in found {
            NSLog("Tippi: \(entry.providerID)'s configured model '\(entry.configured)' is not in its live catalogue — suggesting '\(entry.suggested ?? "none available")'")
        }
        possiblyStale = Set(found.map(\.providerID))
        staleDetails = Dictionary(uniqueKeysWithValues: found.map { ($0.providerID, $0) })
        lastCheckedAt = Date()
    }
}
