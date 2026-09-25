import XCTest
@testable import Tippi

@MainActor
final class ProviderModelPresetsTests: XCTestCase {
    private let suites = ThrowawayDefaults()
    override func tearDown() { suites.removeAll(); super.tearDown() }

    /// Regression (2026-09-25): the OpenRouter presets used
    /// `google/gemini-flash-latest` (404 at OpenRouter) and
    /// `anthropic/claude-haiku-4-5` (only an alias of the dotted id). Users who
    /// already picked them must be moved to the catalogue ids.
    func testOpenRouterPresetsFromBeforeTheCatalogueCheckAreMigrated() {
        let defaults = suites.make()
        defaults.set("google/gemini-flash-latest", forKey: "defaultModel.openrouter")
        defaults.set("anthropic/claude-haiku-4-5", forKey: "dictation.postProcess.modelOverride")

        ProviderModelPresets.migrateRetiredModels(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "defaultModel.openrouter"), "~google/gemini-flash-latest")
        XCTAssertEqual(defaults.string(forKey: "dictation.postProcess.modelOverride"), "anthropic/claude-haiku-4.5")
    }

    /// A migration target nobody can pick in the UI is a trap: the user lands on
    /// an id the picker doesn't show. Every replacement must be a current preset
    /// of the same provider.
    func testEveryRetirementTargetIsACurrentPreset() {
        for retired in ProviderModelPresets.retiredModels {
            let ids = ProviderModelPresets.presets(for: retired.providerID).map(\.id)
            XCTAssertTrue(ids.contains(retired.replacementID),
                          "\(retired.providerID): '\(retired.replacementID)' is not a preset")
        }
    }

    /// The reverse trap: a dead id that is also still offered as a preset would
    /// be rewritten away on every launch after the user picked it.
    func testNoCurrentPresetIsMarkedRetired() {
        for retired in ProviderModelPresets.retiredModels {
            let ids = ProviderModelPresets.presets(for: retired.providerID).map(\.id)
            XCTAssertFalse(ids.contains(retired.deadID),
                           "\(retired.providerID): '\(retired.deadID)' is both a preset and retired")
        }
    }

    /// Opus 5 is superseded as the premium preset but NOT retired (not before
    /// 2027-07-24) — a stored `claude-opus-5` must be left alone.
    func testOpus5SelectionIsNotRewritten() {
        let defaults = suites.make()
        defaults.set("claude-opus-5", forKey: "defaultModel.anthropic")

        ProviderModelPresets.migrateRetiredModels(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "defaultModel.anthropic"), "claude-opus-5")
    }
}
