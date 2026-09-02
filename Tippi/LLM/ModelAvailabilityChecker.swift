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

    /// Provider ids whose configured model was NOT found in that provider's
    /// live catalogue on the last check. Empty until the first check
    /// completes, or if every check failed/was skipped.
    @Published private(set) var possiblyStale: Set<String> = []
    @Published private(set) var lastCheckedAt: Date?

    private init() {}

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

        let results: [(id: String, stale: Bool)] = await withTaskGroup(of: (String, Bool).self) { group in
            for provider in configured {
                group.addTask {
                    let configuredModel = UserDefaults.standard.string(forKey: "defaultModel.\(provider.id)")
                        ?? provider.defaultModel
                    guard let catalog = try? await provider.fetchModelCatalog(),
                          catalog.isComplete,
                          !catalog.ids.isEmpty else {
                        // Fetch failed, provider has no live catalogue, or the
                        // list came back paginated/partial → "not stale".
                        // Never warn on incomplete data: a truncated catalogue
                        // makes working models look retired, which is exactly
                        // how v1.21.0 falsely flagged claude-haiku-4-5.
                        return (provider.id, false)
                    }
                    return (provider.id, !catalog.plausiblyServes(configuredModel))
                }
            }
            var collected: [(String, Bool)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let stale = Set(results.filter(\.stale).map(\.id))
        for id in stale {
            NSLog("Tippi: \(id)'s configured model was not found in its live catalogue — may have been retired")
        }
        possiblyStale = stale
        lastCheckedAt = Date()
    }
}
