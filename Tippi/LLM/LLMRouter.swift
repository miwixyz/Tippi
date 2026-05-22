import Foundation

struct CompletionResult {
    let text: String
    let providerDisplay: String  // e.g. "OpenAI / gpt-4o-mini"
    let duration: TimeInterval
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
        let ordered = orderedProviders()

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
                    duration: Date().timeIntervalSince(start)
                )
            } catch LLMError.noAPIKey {
                continue
            } catch {
                if isUnavailableLocalProvider(provider, error: error) {
                    continue
                }
                throw error
            }
        }

        throw LLMError.noProviderConfigured
    }

    @MainActor
    func anyProviderConfigured() -> Bool {
        for provider in providers {
            if !provider.requiresAPIKey { return true }
            if hasAPIKey(for: provider.id) { return true }
        }
        return false
    }

    private func orderedProviders() -> [LLMProvider] {
        let preferred = Self.preferredProviderID
        return providers.sorted { a, b in
            if a.id == preferred { return true }
            if b.id == preferred { return false }
            return false
        }
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
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            return true
        default:
            return false
        }
    }
}
