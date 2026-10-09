import XCTest
@testable import Tippi

/// 2.24.0 (2026-10-09): Kimi, Scaleway, Groq and Nebius are gone; Haiku 5.5 gets low effort.
@MainActor
final class RemovedProvidersTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "RemovedProvidersTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testRouterNoLongerShipsRemovedProviders() {
        let ids = Set(LLMRouter.allProviders.map(\.id))
        XCTAssertTrue(ids.isDisjoint(with: ProviderModelPresets.removedProviderIDs), "\(ids)")
        for id in ProviderModelPresets.removedProviderIDs {
            XCTAssertTrue(ProviderModelPresets.presets(for: id).isEmpty, id)
        }
    }

    func testMigrationClearsChoicesPointingAtRemovedProviders() {
        let d = freshDefaults()
        let promptID = DemoPrompt.builtIn.first!.id
        d.set("groq", forKey: "defaultProvider")
        d.set("nebius", forKey: "dictation.postProcess.providerOverride")
        d.set("Qwen/Qwen3-30B-A3B-Instruct-2507", forKey: "dictation.postProcess.modelOverride")
        d.set("kimi", forKey: "prompt.providerOverride.\(promptID).provider")
        d.set("kimi-k2", forKey: "prompt.providerOverride.\(promptID).model")
        d.set("llama-3.1-8b-instruct", forKey: "defaultModel.scaleway")

        ProviderModelPresets.migrateRemovedProviders(defaults: d)

        XCTAssertNil(d.string(forKey: "defaultProvider"))
        XCTAssertNil(d.string(forKey: "dictation.postProcess.providerOverride"))
        XCTAssertNil(d.string(forKey: "dictation.postProcess.modelOverride"))
        XCTAssertNil(d.string(forKey: "prompt.providerOverride.\(promptID).provider"))
        XCTAssertNil(d.string(forKey: "prompt.providerOverride.\(promptID).model"))
        XCTAssertNil(d.string(forKey: "defaultModel.scaleway"))
    }

    func testMigrationLeavesRemainingProvidersAlone() {
        let d = freshDefaults()
        d.set("mistral", forKey: "defaultProvider")
        d.set("anthropic", forKey: "dictation.postProcess.providerOverride")
        d.set("claude-haiku-4-5", forKey: "dictation.postProcess.modelOverride")

        ProviderModelPresets.migrateRemovedProviders(defaults: d)

        XCTAssertEqual(d.string(forKey: "defaultProvider"), "mistral")
        XCTAssertEqual(d.string(forKey: "dictation.postProcess.providerOverride"), "anthropic")
        XCTAssertEqual(d.string(forKey: "dictation.postProcess.modelOverride"), "claude-haiku-4-5")
    }

    func testHaiku55GetsLowEffortWithoutThinkingAndNoTemperature() {
        XCTAssertTrue(AnthropicProvider.usesLowEffortNoThinking("claude-haiku-5-5"))
        XCTAssertFalse(AnthropicProvider.usesLowEffortNoThinking("claude-haiku-4-5"))
        XCTAssertFalse(AnthropicProvider.usesLowEffortNoThinking("claude-sonnet-5"))
        XCTAssertFalse(AnthropicProvider.acceptsTemperature("claude-haiku-5-5"))
        XCTAssertTrue(AnthropicProvider.acceptsTemperature("claude-haiku-4-5"))
    }

    func testHaiku45StaysTheDefaultPolishModel() {
        XCTAssertEqual(ProviderModelPresets.defaultPolishModel(for: "anthropic"), "claude-haiku-4-5")
        XCTAssertTrue(ProviderModelPresets.presets(for: "anthropic").contains { $0.id == "claude-haiku-5-5" })
    }
}
