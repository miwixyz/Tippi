import Foundation

struct MistralProvider: OpenAICompatibleProvider {
    let id = "mistral"
    let displayName = "Mistral"
    let defaultModel = "mistral-small-latest"  // alias auto-updates to current small model
    let requiresAPIKey = true

    let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")!
}
