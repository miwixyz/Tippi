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
///
/// These assertions compare against the localized templates rather than English
/// words. An earlier version matched substrings like "Start it again" and broke
/// the moment the strings were translated — the test was pinning wording when
/// the logic under test is *which* message gets chosen.
final class MLXFailureMessageTests: XCTestCase {

    private var stalled: String { String(localized: "mlx.error.stalled") }
    private var noProgress: String { String(localized: "mlx.error.noProgress") }
    private var noAnswer: String { String(localized: "mlx.error.noAnswer") }

    /// The leading fixed part of a format template, up to the first placeholder —
    /// enough to identify which template produced a filled-in message.
    private func stem(_ template: String) -> String {
        let head = template.components(separatedBy: "%").first ?? template
        return String(head.prefix(40))
    }

    func testBytesActuallyMovedSelectsTheStalledDownloadMessage() {
        let msg = MLXServerManager.failureMessage(
            lastProgress: "model.safetensors: 45%|████▌ | 1.80G/4.00G [01:23<01:41, 21.7MB/s]"
        )
        XCTAssertTrue(msg.hasPrefix(stem(stalled)),
                      "Bytes were moving and stopped — that is the one case where the link is a fair suspect.")
    }

    func testTheFetchingPreambleMustNotSelectTheConnectionMessage() {
        // The exact line from the report. It appears even when every file is
        // already local, so it must never produce the "check the connection"
        // message.
        let msg = MLXServerManager.failureMessage(lastProgress: "Fetching 8 files 0% (0/8)")

        XCTAssertFalse(msg.hasPrefix(stem(stalled)),
                       "This line says nothing about the network — blaming it sends the user the wrong way.")
        XCTAssertTrue(msg.hasPrefix(stem(noProgress)))
    }

    func testNoProgressLineAtAllSelectsTheGenericMessage() {
        XCTAssertEqual(MLXServerManager.failureMessage(lastProgress: nil), noAnswer)
    }

    func testTheThreeCasesProduceThreeDifferentMessages() {
        // Guards against a refactor collapsing branches: if two of these ever
        // return the same text, one cause is being mislabelled as another.
        let a = MLXServerManager.failureMessage(lastProgress: nil)
        let b = MLXServerManager.failureMessage(lastProgress: "Fetching 8 files 0% (0/8)")
        let c = MLXServerManager.failureMessage(lastProgress: "weights: 12%| | 500MB/4.0GB")

        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
        XCTAssertNotEqual(a, c)
    }

    func testTheProgressTextIsCarriedIntoTheMessage() {
        // The user needs the last thing that happened, not just a category.
        let progress = "Fetching 8 files 0% (0/8)"
        XCTAssertTrue(MLXServerManager.failureMessage(lastProgress: progress).contains(progress))
    }

    func testNoVariantIsEmpty() {
        for progress in [nil, "Fetching 8 files 0% (0/8)", "model.safetensors: 45%|█| 1.8G/4.0G"] as [String?] {
            XCTAssertFalse(MLXServerManager.failureMessage(lastProgress: progress).isEmpty)
        }
    }

    /// The templates themselves must keep their instruction. This is the part
    /// that made the original message useless — a symptom with no next step.
    func testEveryTemplateNamesANextStep() {
        for (name, template) in [("stalled", stalled), ("noProgress", noProgress), ("noAnswer", noAnswer)] {
            XCTAssertTrue(
                template.localizedCaseInsensitiveContains("start")
                    || template.localizedCaseInsensitiveContains("starten")
                    || template.localizedCaseInsensitiveContains("prüfen")
                    || template.localizedCaseInsensitiveContains("check"),
                "\(name) has no instruction — a symptom without a next step is the bug this change is about."
            )
        }
    }
}
