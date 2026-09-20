import XCTest
@testable import Tippi

/// Covers what Tippi does with a port that is occupied but silent.
///
/// Measured on 2026-09-20: an orphaned `mlx_lm.server` from an earlier Tippi
/// crash held port 8080 for 27 minutes. PPID 1, 0 % CPU, 22 MB resident — the
/// model never loaded. It accepted connections and closed them empty, because
/// the server logs every request to stderr and that pipe pointed at the dead
/// parent: the write failed, the handler died, the reply never came.
///
/// The reuse path only ever handled a listener that *answers*. A silent one
/// fell through to spawning a second server, which could not bind, which
/// surfaced as a startup timeout blaming the download. Every attempt failed
/// identically regardless of model — reported as "Fehler kommt bei allen MLX
/// Modellen". The port was the reason.
final class MLXPortOccupancyTests: XCTestCase {

    func testNothingListeningIsFree() {
        XCTAssertEqual(
            MLXServerManager.occupantVerdict(listenerPID: nil, listenerCommand: nil),
            .free
        )
    }

    func testTheOrphanedServerIsRecognisedAsStale() {
        // The exact command line observed on the reporting machine.
        let command = "/Users/x/.cache/uv/archive-v0/abc/bin/python "
            + "/Users/x/.cache/uv/archive-v0/abc/bin/mlx_lm.server "
            + "--model mlx-community/gemma-4-e2b-it-4bit --port 8080 --host 127.0.0.1"

        XCTAssertEqual(
            MLXServerManager.occupantVerdict(listenerPID: 4992, listenerCommand: command),
            .staleMLXServer(pid: 4992)
        )
    }

    func testTheUvWrapperCountsTooAAndIsNotMissed() {
        // Tippi launches through uvx, so the parent carries a different command
        // line than the python child. Missing it would leave the wrapper alive.
        let command = "/Users/x/.local/bin/uv tool uvx --from mlx-lm mlx_lm.server --port 8080"

        XCTAssertEqual(
            MLXServerManager.occupantVerdict(listenerPID: 4991, listenerCommand: command),
            .staleMLXServer(pid: 4991)
        )
    }

    func testAForeignProgramIsNamedAndNeverClassifiedAsKillable() {
        // LM Studio, llama.cpp, a dev server — not ours. Killing someone else's
        // process because it sits on a port we want is not a fix.
        let command = "/Applications/LM Studio.app/Contents/MacOS/LM Studio --server"
        let verdict = MLXServerManager.occupantVerdict(listenerPID: 777, listenerCommand: command)

        XCTAssertEqual(verdict, .foreignProcess(pid: 777, command: command))
        if case .staleMLXServer = verdict {
            XCTFail("A foreign process must never be classified as safe to terminate.")
        }
    }

    func testAPIDWithoutACommandIsTreatedAsForeign() {
        // `ps` can fail or race the process exiting. Unknown means hands off.
        let verdict = MLXServerManager.occupantVerdict(listenerPID: 123, listenerCommand: "")
        XCTAssertEqual(verdict, .foreignProcess(pid: 123, command: ""))
    }

    func testHalfInformationIsTreatedAsFree() {
        // A pid without a command line, or the reverse, means the lookup did not
        // complete. Acting on half an answer is how the wrong process gets killed.
        XCTAssertEqual(MLXServerManager.occupantVerdict(listenerPID: 42, listenerCommand: nil), .free)
        XCTAssertEqual(MLXServerManager.occupantVerdict(listenerPID: nil, listenerCommand: "mlx_lm.server"), .free)
    }
}
