import XCTest
@testable import Tippi

/// Provider fixes from the 2026-09-27 audit (group A).
final class ProviderAuditFixTests: XCTestCase {

    /// Records what reaches the provider. Before the fix, a call through
    /// `any LLMProvider` was bound statically to the extension default and the
    /// hint never arrived (measured: nil instead of 0.1).
    private final class Spy: LLMProvider, @unchecked Sendable {
        let id = "spy", displayName = "Spy", defaultModel = "m", requiresAPIKey = false
        var received: Double??
        func complete(systemPrompt: String, userText: String, model: String) async throws -> String { "" }
        func complete(systemPrompt: String, userText: String, model: String, temperature: Double?) async throws -> String {
            received = .some(temperature); return ""
        }
        func completeStream(systemPrompt: String, userText: String, model: String) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func fetchModelCatalog() async throws -> ModelCatalog { ModelCatalog(ids: [], isComplete: false) }
    }

    func testTemperatureHintReachesProviderThroughExistential() async throws {
        let spy = Spy()
        let provider: any LLMProvider = spy
        _ = try await provider.complete(systemPrompt: "", userText: "", model: "", temperature: 0.1)
        XCTAssertEqual(spy.received, .some(0.1))
    }

    /// `…/v1/chat/completions` → `…/v1/models` (was `…/v1/chat/models`, a 404).
    func testModelsURLIsTwoSegmentsUp() {
        let providers: [any OpenAICompatibleProvider] = [
            OpenAIProvider(), MistralProvider(), OpenRouterProvider(),
        ]
        for p in providers {
            let url = p.modelsURL.absoluteString
            XCTAssertTrue(url.hasSuffix("/v1/models"), "\(p.id): \(url)")
            XCTAssertFalse(url.contains("/chat/"), "\(p.id): \(url)")
        }
    }

    /// Newer Claude models answer a `temperature` field with a 400.
    func testAnthropicSendsTemperatureOnlyToModelsThatTakeIt() {
        XCTAssertTrue(AnthropicProvider.acceptsTemperature("claude-haiku-4-5"))
        XCTAssertTrue(AnthropicProvider.acceptsTemperature("claude-sonnet-4-6"))
        for model in ["claude-sonnet-5", "claude-opus-5", "claude-opus-5-5", "claude-opus-4-8", "claude-fable-5-1"] {
            XCTAssertFalse(AnthropicProvider.acceptsTemperature(model), model)
        }
    }
}
