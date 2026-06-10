import Foundation

protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var defaultModel: String { get }
    var requiresAPIKey: Bool { get }

    func complete(
        systemPrompt: String,
        userText: String,
        model: String
    ) async throws -> String
}

enum LLMError: LocalizedError {
    case noProviderConfigured
    case noAPIKey(provider: String)
    case httpError(status: Int, body: String)
    case invalidResponse
    case truncated
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No AI provider is configured."
        case .noAPIKey(let provider):
            return "No API key saved for \(provider). Add one in Settings → Providers."
        case .httpError(let status, let body):
            return "\(provider(forStatus: status)) (HTTP \(status)): \(body.prefix(240))"
        case .invalidResponse:
            return "Could not parse the AI response."
        case .truncated:
            return "The AI response was cut off (output length limit reached). Try a shorter text."
        case .cancelled:
            return "Cancelled."
        }
    }

    private func provider(forStatus status: Int) -> String {
        switch status {
        case 401, 403: return "API key invalid or unauthorized"
        case 429: return "Rate limit reached"
        case 500..<600: return "Provider server error"
        default: return "Network error"
        }
    }
}
