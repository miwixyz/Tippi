import XCTest
@testable import Tippi

/// Covers when Tippi is allowed to interrupt the user about a problem.
///
/// Background (2026-09-20): the menubar showed a bare "Fehler", the cause lived
/// in a settings pane, and nothing announced it. The fix adds a notification —
/// which immediately creates the opposite risk, because `TippiStatusMonitor`
/// recomputes every 3 seconds. A notification per tick would be worse than
/// silence, and the first thing Michael would do is switch it off. These tests
/// pin the rule that keeps that from happening.
@MainActor
final class ProblemNotifierTests: XCTestCase {

    private func problem(_ headline: String, _ action: String = "do the thing")
        -> TippiStatusMonitor.Problem {
        .init(headline: headline, action: action)
    }

    override func setUp() {
        super.setUp()
        ProblemNotifier.shared.resetForTesting()
    }

    override func tearDown() {
        ProblemNotifier.shared.resetForTesting()
        super.tearDown()
    }

    func testEnteringAProblemAnnouncesIt() {
        let p = problem("Local server is not running")
        XCTAssertEqual(ProblemNotifier.shared.decide(.error(p)), p)
    }

    func testTheSameProblemNeverAnnouncesTwice() {
        // The monitor recomputes every 3 s; without this the user gets a
        // notification every three seconds for as long as the server is down.
        let p = problem("Local server is not running")
        _ = ProblemNotifier.shared.decide(.error(p))

        XCTAssertNil(ProblemNotifier.shared.decide(.error(p)))
        XCTAssertNil(ProblemNotifier.shared.decide(.error(p)))
    }

    func testADifferentProblemAnnouncesEvenWithoutRecoveryInBetween() {
        // "Server stopped" turning into "download stalled" is new information.
        _ = ProblemNotifier.shared.decide(.error(problem("Local server is not running")))
        let second = problem("Local server failed", "Model download stalled — check the connection")

        XCTAssertEqual(ProblemNotifier.shared.decide(.error(second)), second)
    }

    func testRecoveryResetsSoTheNextOccurrenceIsAnnouncedAgain() {
        let p = problem("Local server is not running")
        _ = ProblemNotifier.shared.decide(.error(p))
        XCTAssertNil(ProblemNotifier.shared.decide(.ready), "Being fine is not an announcement.")

        XCTAssertEqual(ProblemNotifier.shared.decide(.error(p)), p,
                       "A problem that came back must be announced again, not swallowed as a repeat.")
    }

    func testHealthyStatesNeverAnnounce() {
        XCTAssertNil(ProblemNotifier.shared.decide(.ready))
        XCTAssertNil(ProblemNotifier.shared.decide(.warming))
    }

    // MARK: - The menubar row

    func testErrorLabelNamesTheCauseInsteadOfJustSayingError() {
        // The original complaint, as a test: "Nur Fehler ist zu wenig Info."
        let status = TippiStatusMonitor.Status.error(problem("Local server is not running"))

        XCTAssertTrue(status.label.contains("Local server is not running"),
                      "The menubar row must name the cause, not only the word Fehler/Error.")
        XCTAssertNotEqual(status.label, String(localized: "status.error"))
    }

    func testEveryProblemCarriesAnAction() {
        // A symptom without a next step is what made the old message useless.
        let status = TippiStatusMonitor.Status.error(problem("something broke", "open Settings and press Start"))
        let action = try? XCTUnwrap(status.problem?.action)

        XCTAssertFalse((action ?? "").isEmpty,
                       "A problem without an instruction is the bug this change fixes.")
    }
}
