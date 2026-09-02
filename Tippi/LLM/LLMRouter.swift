import Foundation

struct CompletionResult {
    let text: String
    let providerDisplay: String  // e.g. "OpenAI / gpt-4o-mini"
    let duration: TimeInterval
    /// Stable provider id (e.g. "openai", "anthropic", "mlx") — useful for logging.
    let providerID: String
    /// Concrete model name used for this call.
    let model: String
}

/// A streaming completion: incremental text deltas plus the resolved provider
/// metadata (known before the first token arrives).
struct StreamingCompletion {
    let stream: AsyncThrowingStream<String, Error>
    let providerDisplay: String
    let providerID: String
    let model: String
}

/// Catalogue of registered providers and where to route requests.
struct LLMRouter {
    static let shared = LLMRouter()

    /// All providers known to Tippi, in default-priority order.
    static let allProviders: [LLMProvider] = [
        OpenAIProvider(),
        AnthropicProvider(),
        GeminiProvider(),
        MistralProvider(),
        ScalewayProvider(),
        GroqProvider(),
        KimiProvider(),
        NebiusProvider(),
        OpenRouterProvider(),
        OllamaProvider(),
        MLXProvider()
    ]

    private var providers: [LLMProvider] { Self.allProviders }

    static var preferredProviderID: String {
        UserDefaults.standard.string(forKey: "defaultProvider") ?? "openai"
    }

    static func setPreferredProvider(_ id: String) {
        UserDefaults.standard.set(id, forKey: "defaultProvider")
    }

    /// Returns the human-readable display name for a provider ID without
    /// making any API call. Used by the recording indicator to show which
    /// provider WILL handle the dictation cleanup step before the call starts.
    static func providerDisplayName(forID id: String) -> String? {
        allProviders.first(where: { $0.id == id })?.displayName
    }

    /// The provider to actually try first. Honours an explicit user choice; if
    /// none is set, picks the first cloud provider that has a key so a fresh
    /// install with e.g. only a Mistral key doesn't silently fall through to a
    /// cold-starting local model (the hard-coded "openai" default would, since
    /// it has no key). Falls back to the first local provider, then "openai".
    @MainActor
    func effectivePreferredProviderID() -> String {
        if let explicit = UserDefaults.standard.string(forKey: "defaultProvider") {
            return explicit
        }
        if let firstKeyed = providers.first(where: { $0.requiresAPIKey && hasAPIKey(for: $0.id) }) {
            return firstKeyed.id
        }
        return providers.first(where: { !$0.requiresAPIKey })?.id ?? "openai"
    }

    private func model(for providerID: String, fallback: String) -> String {
        UserDefaults.standard.string(forKey: "defaultModel.\(providerID)") ?? fallback
    }

    @MainActor
    private func hasAPIKey(for providerID: String) -> Bool {
        KeychainStore.hasAPIKey(for: providerID)
    }

    /// Try the preferred provider first. If it needs an API key and none is set,
    /// fall through to the next configured provider. Throws `.noProviderConfigured`
    /// if nothing usable is available.
    func complete(systemPrompt: String, userText: String) async throws -> CompletionResult {
        await MainActor.run { AIActivityMonitor.shared.begin() }
        defer { Task { await MainActor.run { AIActivityMonitor.shared.end() } } }
        let preferred = await MainActor.run { effectivePreferredProviderID() }
        let ordered = orderedProviders(preferred: preferred)
        let fallbackOn = Self.allowProviderFallback

        var lastError: Error?
        for provider in ordered {
            if provider.requiresAPIKey {
                let hasKey = await MainActor.run { hasAPIKey(for: provider.id) }
                if !hasKey { continue }
            }
            do {
                let modelName = model(for: provider.id, fallback: provider.defaultModel)
                let start = Date()
                let text = try await provider.complete(
                    systemPrompt: systemPrompt,
                    userText: userText,
                    model: modelName
                )
                return CompletionResult(
                    text: text,
                    providerDisplay: "\(provider.displayName) / \(modelName)",
                    duration: Date().timeIntervalSince(start),
                    providerID: provider.id,
                    model: modelName
                )
            } catch LLMError.noAPIKey {
                continue
            } catch {
                lastError = error
                // Unavailable local provider (server not running) → always try
                // the next one.
                if isUnavailableLocalProvider(provider, error: error) {
                    continue
                }
                // Opt-in: on a transient cloud error (rate limit / server error
                // / network), try the next configured provider. This sends the
                // text to a second provider, so it's off by default (privacy).
                if fallbackOn, Self.isRetriableCloudError(error) {
                    NSLog("Tippi LLM: \(provider.id) failed (\(error.localizedDescription)) — falling back to next provider")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? LLMError.noProviderConfigured
    }

    /// Streaming variant of `complete`. Picks the first eligible provider (same
    /// preference logic) and returns its delta stream. Unlike `complete`, there
    /// is no mid-stream fallthrough — once a provider is chosen, an error
    /// surfaces through the stream (the interactive Preview shows it and lets
    /// the user retry / pick another provider).
    func completeStream(systemPrompt: String, userText: String) async throws -> StreamingCompletion {
        let preferred = await MainActor.run { effectivePreferredProviderID() }
        let ordered = orderedProviders(preferred: preferred)

        for provider in ordered {
            if provider.requiresAPIKey {
                let hasKey = await MainActor.run { hasAPIKey(for: provider.id) }
                if !hasKey { continue }
            }
            let modelName = model(for: provider.id, fallback: provider.defaultModel)
            return StreamingCompletion(
                stream: provider.completeStream(
                    systemPrompt: systemPrompt,
                    userText: userText,
                    model: modelName
                ),
                providerDisplay: "\(provider.displayName) / \(modelName)",
                providerID: provider.id,
                model: modelName
            )
        }

        throw LLMError.noProviderConfigured
    }

    /// Whether a failed cloud provider may fall through to the next configured
    /// one. Off by default — fallback re-sends the user's text to another
    /// provider, which is a privacy choice the user opts into.
    static var allowProviderFallback: Bool {
        UserDefaults.standard.bool(forKey: "allowProviderFallback")
    }

    /// Transient cloud failures worth retrying on another provider: rate limits,
    /// 5xx server errors, and network/timeout errors. A 401/403 (bad key) is
    /// also retriable on a *different* provider, so include it.
    private static func isRetriableCloudError(_ error: Error) -> Bool {
        if case let LLMError.httpError(status, _) = error {
            return status == 429 || status == 401 || status == 403 || (500..<600).contains(status)
        }
        if error is URLError { return true }
        return false
    }

    /// Variant of `complete` that targets a specific provider + model — used
    /// by the dictation polish path when the user has chosen a "polish
    /// provider override" different from the chat provider. Falls back to
    /// the normal `complete` if the specified provider is unknown or has no
    /// API key configured.
    func complete(
        systemPrompt: String,
        userText: String,
        forceProviderID: String,
        forceModel: String
    ) async throws -> CompletionResult {
        await MainActor.run { AIActivityMonitor.shared.begin() }
        defer { Task { await MainActor.run { AIActivityMonitor.shared.end() } } }
        guard !forceProviderID.isEmpty,
              let provider = Self.allProviders.first(where: { $0.id == forceProviderID }) else {
            return try await complete(systemPrompt: systemPrompt, userText: userText)
        }
        if provider.requiresAPIKey {
            let hasKey = await MainActor.run { hasAPIKey(for: provider.id) }
            guard hasKey else {
                return try await complete(systemPrompt: systemPrompt, userText: userText)
            }
        }
        let modelName = forceModel.isEmpty ? provider.defaultModel : forceModel
        let start = Date()
        let text = try await provider.complete(
            systemPrompt: systemPrompt,
            userText: userText,
            model: modelName
        )
        return CompletionResult(
            text: text,
            providerDisplay: "\(provider.displayName) / \(modelName)",
            duration: Date().timeIntervalSince(start),
            providerID: provider.id,
            model: modelName
        )
    }

    /// Streaming counterpart to the forced `complete` above — same "force a
    /// specific provider/model, fall back to the normal resolution if it's
    /// unusable" contract, for the per-prompt provider override.
    func completeStream(
        systemPrompt: String,
        userText: String,
        forceProviderID: String,
        forceModel: String
    ) async throws -> StreamingCompletion {
        guard !forceProviderID.isEmpty,
              let provider = Self.allProviders.first(where: { $0.id == forceProviderID }) else {
            return try await completeStream(systemPrompt: systemPrompt, userText: userText)
        }
        if provider.requiresAPIKey {
            let hasKey = await MainActor.run { hasAPIKey(for: provider.id) }
            guard hasKey else {
                return try await completeStream(systemPrompt: systemPrompt, userText: userText)
            }
        }
        let modelName = forceModel.isEmpty ? provider.defaultModel : forceModel
        return StreamingCompletion(
            stream: provider.completeStream(
                systemPrompt: systemPrompt,
                userText: userText,
                model: modelName
            ),
            providerDisplay: "\(provider.displayName) / \(modelName)",
            providerID: provider.id,
            model: modelName
        )
    }

    @MainActor
    func anyProviderConfigured() -> Bool {
        for provider in providers {
            if !provider.requiresAPIKey { return true }
            if hasAPIKey(for: provider.id) { return true }
        }
        return false
    }

    private func orderedProviders(preferred: String = LLMRouter.preferredProviderID) -> [LLMProvider] {
        // Move the preferred provider to the front, keep the registry order for
        // the rest. Avoids `sorted` with a non-strict-weak-ordering predicate
        // (undefined behaviour in Swift).
        guard let idx = providers.firstIndex(where: { $0.id == preferred }) else {
            return providers
        }
        var rest = providers
        let pick = rest.remove(at: idx)
        return [pick] + rest
    }

    private func isUnavailableLocalProvider(_ provider: LLMProvider, error: Error) -> Bool {
        guard !provider.requiresAPIKey else { return false }

        if let mlxError = error as? MLXError {
            switch mlxError {
            case .serverNotFound, .startupTimeout, .launchFailed:
                return true
            }
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch URLError.Code(rawValue: nsError.code) {
        // .timedOut is deliberately NOT here: a slow local model that is still
        // generating must surface as an error — falling through would silently
        // send the user's text to the next (cloud) provider.
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}
