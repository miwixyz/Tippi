import XCTest
@testable import Tippi

/// Apple Intelligence as the eighth provider (2026-10-27). No live call here —
/// whether the model is available depends on the Mac; the measurement lives in
/// `scripts/apple-intelligence-messung/`.
final class AppleIntelligenceProviderTests: XCTestCase {

    func testRegisteredAsLocalProviderWithoutKey() throws {
        let provider = try XCTUnwrap(LLMRouter.allProviders.first { $0.id == "apple" })
        // No key = local for the router: a local choice never falls through to the cloud.
        XCTAssertFalse(provider.requiresAPIKey)
        XCTAssertEqual(provider.defaultModel, "system")
    }

    /// The dictation polish override picks `defaultPolishModel` — it must land
    /// on the one id the provider has.
    func testOnlyPresetIsTheSystemModel() {
        XCTAssertEqual(ProviderModelPresets.presets(for: "apple").map(\.id), ["system"])
        XCTAssertEqual(ProviderModelPresets.defaultPolishModel(for: "apple"), "system")
    }

    /// The cleanup hint must map to greedy. `sampling(forTemperatureHint:)`
    /// hard-codes 0.1 because its file must not depend on other Tippi types —
    /// this pins it to the real constant.
    func testCleanupHintSamplesGreedy() {
        XCTAssertEqual(AppleIntelligenceModel.sampling(forTemperatureHint: TaskTemperature.transcriptCleanup), .greedy)
        XCTAssertEqual(AppleIntelligenceModel.sampling(forTemperatureHint: nil), .temperature(0.3))
        XCTAssertEqual(AppleIntelligenceModel.sampling(forTemperatureHint: 0.7), .temperature(0.7))
    }

    /// Only "the model can't run" may send the router on to the next local
    /// provider; a declined or too-long text is the answer for this request.
    func testOnlyUnavailabilityCountsAsUnavailable() {
        let unavailable: [AppleIntelligenceError] = [.requiresNewerMacOS, .deviceNotEligible, .notEnabled, .modelNotReady, .unavailable]
        let failed: [AppleIntelligenceError] = [.textTooLong, .rejected, .unsupportedLanguage, .busy, .failed]
        XCTAssertTrue(unavailable.allSatisfy(\.isUnavailability))
        XCTAssertFalse(failed.contains(where: \.isUnavailability))
    }

    /// The dictation toast and the Preview show `localizedDescription` — a
    /// missing string would put the raw key on screen.
    func testEveryErrorHasASentenceInBothLanguages() throws {
        let all: [AppleIntelligenceError] = [.requiresNewerMacOS, .deviceNotEligible, .notEnabled, .modelNotReady, .unavailable,
                                             .textTooLong, .rejected, .unsupportedLanguage, .busy, .failed]
        for error in all {
            let text = try XCTUnwrap(error.errorDescription)
            XCTAssertFalse(text.hasPrefix("llm.apple."), "missing string for \(error)")
        }
        let de = try XCTUnwrap(Bundle.main.path(forResource: "de", ofType: "lproj").flatMap(Bundle.init(path:)))
        for key in ["llm.apple.error.notEnabled", "llm.apple.error.rejected", "settings.providers.hint.apple",
                    "settings.providers.apple.ready", "status.error.appleUnavailable"] {
            XCTAssertNotEqual(de.localizedString(forKey: key, value: nil, table: nil), key, key)
        }
    }

    /// On this Mac the framework either answers or names a reason — never a
    /// crash, never `.requiresNewerMacOS` on macOS 26+.
    func testAvailabilityMatchesTheSystemVersion() {
        let reason = AppleIntelligenceModel.unavailableReason
        if #available(macOS 26, *) {
            XCTAssertNotEqual(reason, .requiresNewerMacOS)
        } else {
            XCTAssertEqual(reason, .requiresNewerMacOS)
        }
    }
}
