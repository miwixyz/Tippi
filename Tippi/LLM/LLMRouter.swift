import Foundation

struct CompletionResult {
    let text: String
    let providerDisplay: String  // e.g. "OpenAI / gpt-4o-mini"
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
        OllamaProvider()
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
                let text = try await provider.complete(
                    systemPrompt: systemPrompt,
                    userText: userText,
                    model: modelName
                )
                return CompletionResult(
                    text: text,
                    providerDisplay: "\(provider.displayName) / \(modelName)"
                )
            } catch LLMError.noAPIKey {
                continue
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
}
