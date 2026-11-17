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

    // MARK: - Nur eigene Server (Audit-Fund 7, 2026-11-17)

    private let binary = "/Users/x/.local/bin/mlx_lm.server"
    /// Die Kommandozeile, wie `ps` sie für Tippis Start zeigt (gemessen 17.11.).
    private var ownCommand: String {
        "/Users/x/.local/share/uv/tools/mlx-lm/bin/python \(binary) "
            + "--model mlx-community/gemma-4-e4b-it-4bit --port 8080 --host 127.0.0.1"
    }

    func testASilentMLXServerOfAnotherLiveProgramIsNeverKilled() {
        // Elternprozess lebt (z. B. die installierte Tippi neben einem Testbuild).
        let verdict = MLXServerManager.occupantVerdict(listenerPID: 87957, listenerCommand: ownCommand,
                                                       listenerParentPID: 87915, ownPID: 500)
        XCTAssertEqual(verdict, .foreignProcess(pid: 87957, command: ownCommand))
    }

    func testASilentOrphanedMLXServerIsStillStale() {
        XCTAssertEqual(MLXServerManager.occupantVerdict(listenerPID: 4992, listenerCommand: ownCommand,
                                                        listenerParentPID: 1, ownPID: 500),
                       .staleMLXServer(pid: 4992))
    }

    func testAnOrphanWithOurCommandLineIsTippisLeftover() {
        // Tippi abgestürzt oder schneller beendet als sein Server: Elternprozess launchd.
        let listener = MLXServerManager.PortListener(pid: 4992, parentPID: 1, command: ownCommand)
        XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: listener, ownPID: 500,
                                                               binaryPath: binary, port: 8080),
                       .leftoverOfTippi(pid: 4992))
    }

    func testOurOwnDyingChildIsALeftoverToo() {
        let listener = MLXServerManager.PortListener(pid: 4992, parentPID: 500, command: ownCommand)
        XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: listener, ownPID: 500,
                                                               binaryPath: binary, port: 8080),
                       .leftoverOfTippi(pid: 4992))
    }

    func testTheSameServerOfAnotherRunningTippiIsForeign() {
        // Genau der Fall vom 17.11.: gleicher Befehl, aber Kind einer anderen, lebenden Tippi.
        let listener = MLXServerManager.PortListener(pid: 87957, parentPID: 87915, command: ownCommand)
        XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: listener, ownPID: 500,
                                                               binaryPath: binary, port: 8080),
                       .foreign(pid: 87957, command: ownCommand))
    }

    func testAnOrphanWithOtherOptionsIsForeign() {
        // Von Hand gestartet, z. B. ohne --host oder auf anderem Port: nicht unser Befehl.
        let byHand = "/Users/x/python \(binary) --model mlx-community/gemma-4-e4b-it-4bit --port 8080"
        let otherBinary = ownCommand.replacingOccurrences(of: binary, with: "/opt/homebrew/bin/mlx_lm.server")
        for command in [byHand, otherBinary] {
            let listener = MLXServerManager.PortListener(pid: 7, parentPID: 1, command: command)
            XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: listener, ownPID: 500,
                                                                   binaryPath: binary, port: 8080),
                           .foreign(pid: 7, command: command), command)
        }
    }

    func testAnOrphanForAnotherModelIsStillOurs() {
        // Nach einem Absturz kann das Modell gewechselt worden sein — der alte Server bleibt unserer.
        let other = ownCommand.replacingOccurrences(of: "gemma-4-e4b", with: "gemma-4-e2b")
        let listener = MLXServerManager.PortListener(pid: 9, parentPID: 1, command: other)
        XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: listener, ownPID: 500,
                                                               binaryPath: binary, port: 8080),
                       .leftoverOfTippi(pid: 9))
    }

    func testAnUnidentifiedAnsweringServerIsForeign() {
        XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: nil, ownPID: 500,
                                                               binaryPath: binary, port: 8080),
                       .foreign(pid: nil, command: ""))
        let noParent = MLXServerManager.PortListener(pid: 3, parentPID: nil, command: ownCommand)
        XCTAssertEqual(MLXServerManager.answeringServerVerdict(listener: noParent, ownPID: 500,
                                                               binaryPath: binary, port: 8080),
                       .foreign(pid: 3, command: ownCommand))
    }

    func testPSLineIsSplitIntoParentAndCommand() {
        let parsed = MLXServerManager.parsePSLine("  87915 /Users/x/python /Users/x/mlx_lm.server --port 8080\n")
        XCTAssertEqual(parsed.parentPID, 87915)
        XCTAssertEqual(parsed.command, "/Users/x/python /Users/x/mlx_lm.server --port 8080")
        XCTAssertNil(MLXServerManager.parsePSLine("").parentPID)
    }

    func testDisplayNamePrefersTheServerOverPython() {
        XCTAssertEqual(MLXServerManager.displayName(ofCommand: ownCommand), "mlx_lm.server")
        XCTAssertEqual(MLXServerManager.displayName(ofCommand: "/usr/bin/llama-server -p 8080"), "llama-server")
    }
}
