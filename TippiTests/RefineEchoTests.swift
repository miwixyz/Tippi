import XCTest
@testable import Tippi

/// 2026-10-14: Gemma 4 E2B (MLX, local) answered the refinement "cooler" with
/// just "Cooler" — 3 of 3 runs against mlx_lm.server with Tippi's exact
/// request. Offered as a result, "Replace" would have swapped the user's whole
/// text for one word.
final class RefineEchoTests: XCTestCase {

    func testEchoedInstructionIsRejected() {
        for echo in ["cooler", "Cooler", "Cooler.", "„cooler“", " \"Cooler!\" \n"] {
            XCTAssertThrowsError(try LLMError.notEcho(echo, of: "cooler"), echo) { error in
                guard case LLMError.echoedInstruction = error else {
                    return XCTFail("wrong error for \(echo): \(error)")
                }
            }
        }
    }

    func testRealResultPasses() throws {
        let rewrite = "Die witzigen Abenteuer von Bud Spencer und Terence Hill sind zurück!"
        XCTAssertEqual(try LLMError.notEcho(rewrite, of: "cooler"), rewrite)
        // No instruction (built-in prompts): never a false alarm.
        XCTAssertEqual(try LLMError.notEcho("Cooler", of: nil), "Cooler")
        // A one-word result is fine when it is not the instruction itself.
        XCTAssertEqual(try LLMError.notEcho("Ja.", of: "antworte kurz"), "Ja.")
    }

    /// The wording that stopped the echo for "cooler" and "formeller" on E2B
    /// and E4B without breaking "kürzer"/"auf Englisch" (measured 2026-10-14).
    func testRefinePromptFramesShortWishAsChange() {
        let prompt = RefinePrompt.system(for: "cooler")
        XCTAssertTrue(prompt.contains("WISH: “cooler”"))
        XCTAssertTrue(prompt.contains("never the answer itself"))
    }
}
