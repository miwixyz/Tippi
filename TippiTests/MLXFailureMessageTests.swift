import XCTest
@testable import Tippi

/// Covers which cause the MLX startup failure blames.
///
/// Real false alarm, 2026-09-20: a fully cached model printed
/// `Fetching 8 files: 0% (0/8)` once and then nothing while 3.3 GB of weights
/// loaded. The silence timeout fired and the message said "Model download
/// stalled — check the connection". Measured at that moment: all 8 files
/// present, huggingface.co answering in 0.18 s, and the server starting in one
/// second when run by hand. Nothing was wrong with the connection, and the
/// message sent the user to look at it.
final class MLXFailureMessageTests: XCTestCase {

    func testBlamesTheDownloadOnlyWhenBytesActuallyMoved() {
        let msg = MLXServerManager.failureMessage(
            lastProgress: "model.safetensors: 45%|████▌ | 1.80G/4.00G [01:23<01:41, 21.7MB/s]"
        )
        XCTAssertTrue(msg.contains("download stalled"))
        XCTAssertTrue(msg.contains("connection"), "Bytes were moving and stopped — the link is a fair suspect.")
    }

    func testDoesNotBlameTheConnectionForTheFetchingPreamble() {
        // The exact line from the report. It appears even when every file is
        // already local, so it must never produce "check the connection".
        let msg = MLXServerManager.failureMessage(lastProgress: "Fetching 8 files 0% (0/8)")

        XCTAssertFalse(msg.contains("Check the connection"),
                       "This line says nothing about the network — blaming it sends the user the wrong way.")
        XCTAssertTrue(msg.contains("not necessarily the problem"))
        XCTAssertTrue(msg.contains("Start it again"), "Every failure message must end in a next step.")
    }

    func testNoProgressAtAllStillGivesANextStep() {
        let msg = MLXServerManager.failureMessage(lastProgress: nil)

        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(msg.contains("Start it again"),
                      "A symptom without an instruction is the bug this whole change is about.")
    }

    func testEveryVariantNamesAnAction() {
        for progress in [nil, "Fetching 8 files 0% (0/8)", "model.safetensors: 45%|█| 1.8G/4.0G"] as [String?] {
            let msg = MLXServerManager.failureMessage(lastProgress: progress)
            XCTAssertTrue(msg.lowercased().contains("start"),
                          "No next step in: \(msg)")
        }
    }
}
