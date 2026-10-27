import Foundation

/// Apple Intelligence — Apple's on-device model on macOS 26+. No key, no
/// install, the text stays on the Mac. On older systems, or with Apple
/// Intelligence switched off, every call throws an `AppleIntelligenceError`
/// that says why; `LLMRouter` treats that like a local server that is not
/// running and tries the next *local* provider, and dictation inserts the raw
/// transcript as with any other failure.
///
/// The model is fixed by the system — there is nothing to choose, so the only
/// preset is "system" and the `model` argument is ignored.
struct AppleIntelligenceProvider: LLMProvider {
    let id = "apple"
    let displayName = "Apple Intelligence (local)"
    let defaultModel = "system"
    let requiresAPIKey = false

    func complete(systemPrompt: String, userText: String, model: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userText: userText, model: model, temperature: nil)
    }

    func complete(systemPrompt: String, userText: String, model _: String,
                  temperature hint: Double?) async throws -> String {
        let text = try await AppleIntelligenceModel.respond(
            instructions: systemPrompt,
            text: userText,
            sampling: AppleIntelligenceModel.sampling(forTemperatureHint: hint)
        )
        // An empty answer is a failure, never a result (Return would delete
        // the selection).
        return try LLMError.nonEmpty(text)
    }
}
