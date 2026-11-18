import XCTest
@testable import Tippi

/// Code-Audit 18.11.: Ollama meldet eine an der Längengrenze abgeschnittene Antwort mit
/// `done_reason: "length"` (Quelle: ollama/llm/server.go, `DoneReasonLength`). Tippi las das Feld nicht
/// und fügte die halbe Antwort ein, als wäre sie fertig. Die anderen Anbieter werfen dafür `.truncated`.
final class OllamaResponseTests: XCTestCase {

    private func body(_ content: String, doneReason: String?) -> Data {
        let reason = doneReason.map { #","done_reason":"\#($0)""# } ?? ""
        return Data(#"{"model":"llama3.3","message":{"role":"assistant","content":"\#(content)"}\#(reason),"done":true}"#.utf8)
    }

    func testCompleteAnswer() throws {
        XCTAssertEqual(try OllamaProvider.content(from: body(" Hallo Welt ", doneReason: "stop")), "Hallo Welt")
    }

    func testTruncatedAnswerIsNotInserted() {
        XCTAssertThrowsError(try OllamaProvider.content(from: body("Die halbe Antw", doneReason: "length"))) { error in
            guard case LLMError.truncated = error else { return XCTFail("expected .truncated, got \(error)") }
        }
    }

    func testOlderOllamaWithoutDoneReasonStillWorks() throws {
        XCTAssertEqual(try OllamaProvider.content(from: body("Ok", doneReason: nil)), "Ok")
    }
}
