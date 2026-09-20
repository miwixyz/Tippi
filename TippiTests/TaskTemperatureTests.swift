import XCTest
@testable import Tippi

/// Covers the per-task temperature hint.
///
/// Background (2026-09-20): every Tippi call went out at 0.3, including the
/// dictation cleanup. 0.3 is a creative-writing default for a task whose whole
/// job is to change as little as possible. Michael had independently pinned 0.1
/// in an Ollama Modelfile for exactly this, which is what prompted the change.
///
/// The dangerous half is not "does the hint apply" — it is "does the hint stay
/// out of the way where a temperature is not allowed at all".
final class TaskTemperatureTests: XCTestCase {

    private func effective(_ providerDefault: Double?, _ hint: Double?) -> Double? {
        OpenAIProvider.effectiveTemperature(providerDefault: providerDefault, hint: hint)
    }

    // MARK: - The rule that protects reasoning models

    func testANilProviderDefaultStaysNilEvenWithAHint() {
        // `temperature(for:)` returning nil means THIS MODEL REJECTS THE FIELD
        // (OpenAI's gpt-5/o1/o3/o4 family), not "no opinion". Sending 0.1 there
        // turns a working call into a 400 — the hint must never resurrect it.
        XCTAssertNil(effective(nil, 0.1))
        XCTAssertNil(effective(nil, 0.9))
        XCTAssertNil(effective(nil, nil))
    }

    func testTheRealReasoningModelsResolveToNilWithAHintPresent() {
        // Guards the wiring, not just the helper: the provider's own model
        // classification has to reach the rule above.
        let provider = OpenAIProvider()
        for model in ["gpt-5", "o1-preview", "o3-mini", "o4-mini"] {
            XCTAssertNil(
                OpenAIProvider.effectiveTemperature(
                    providerDefault: provider.temperature(for: model),
                    hint: TaskTemperature.transcriptCleanup
                ),
                "\(model) rejects a temperature — the cleanup hint must not add one."
            )
        }
    }

    // MARK: - The ordinary path

    func testTheHintWinsOverTheProviderDefault() {
        XCTAssertEqual(effective(0.3, 0.1), 0.1)
    }

    func testWithoutAHintTheProviderDefaultIsUntouched() {
        // Everything that is not dictation cleanup must keep behaving exactly
        // as before — rewriting, translating, the prompt library.
        XCTAssertEqual(effective(0.3, nil), 0.3)
    }

    func testANonReasoningModelAcceptsTheCleanupHint() {
        let provider = OpenAIProvider()
        XCTAssertEqual(
            OpenAIProvider.effectiveTemperature(
                providerDefault: provider.temperature(for: "gpt-4o-mini"),
                hint: TaskTemperature.transcriptCleanup
            ),
            TaskTemperature.transcriptCleanup
        )
    }

    // MARK: - The value itself

    func testCleanupTemperatureIsLowEnoughToBeWorthTheChange() {
        // A hint that lands near the old 0.3 would be churn. This exists to
        // make a future "let's raise it a bit" a deliberate act.
        XCTAssertLessThanOrEqual(TaskTemperature.transcriptCleanup, 0.15)
        XCTAssertGreaterThanOrEqual(TaskTemperature.transcriptCleanup, 0.0)
    }
}
