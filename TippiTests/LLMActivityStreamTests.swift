import XCTest
@testable import Tippi

/// `LLMRouter.monitored` is what lights the menubar activity indicator during a
/// *streamed* response. `complete` gets this from a plain `defer`; a stream
/// returns before the work happens, so the begin/end pair has to travel with
/// the stream. Until the audit of 2026-09-19 it did not travel at all and the
/// indicator stayed dark on the default path.
///
/// What these tests actually guard is the other half: the counter must come
/// back to zero on *every* exit — normal end, thrown error, and a caller that
/// walks away mid-stream. An unbalanced counter pins the indicator to "busy"
/// for the rest of the session, which is worse than never lighting it.
final class LLMActivityStreamTests: XCTestCase {

    private func makeStream(_ body: @escaping (AsyncThrowingStream<String, Error>.Continuation) -> Void)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in body(continuation) }
    }

    /// The end is posted from a detached hop to the main actor, so it lands a
    /// beat after the stream itself finishes.
    @MainActor
    private func waitForIdle(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while AIActivityMonitor.shared.isActive, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    func testIndicatorIsActiveWhileStreamingAndIdleAfterwards() async throws {
        try await waitForIdle()
        XCTAssertFalse(AIActivityMonitor.shared.isActive, "precondition: nothing else in flight")

        let upstream = makeStream { continuation in
            continuation.yield("hello")
            continuation.yield(" world")
            continuation.finish()
        }

        var received = ""
        var sawActive = false
        for try await delta in LLMRouter.monitored(upstream) {
            received += delta
            if AIActivityMonitor.shared.isActive { sawActive = true }
        }

        XCTAssertEqual(received, "hello world", "the wrapper must forward every delta unchanged")
        XCTAssertTrue(sawActive, "the indicator must be lit while deltas are arriving")
        try await waitForIdle()
        XCTAssertFalse(AIActivityMonitor.shared.isActive, "the indicator must go dark once the stream ends")
    }

    @MainActor
    func testErrorStillBalancesTheCounter() async throws {
        try await waitForIdle()

        struct Boom: Error {}
        let upstream = makeStream { continuation in
            continuation.yield("partial")
            continuation.finish(throwing: Boom())
        }

        var thrown: Error?
        do {
            for try await _ in LLMRouter.monitored(upstream) {}
        } catch {
            thrown = error
        }

        XCTAssertTrue(thrown is Boom, "the wrapper must not swallow or replace the provider's error")
        try await waitForIdle()
        XCTAssertFalse(AIActivityMonitor.shared.isActive, "a failed request must not leave the indicator lit")
    }

    /// `PreviewView` breaks out of its loop when the task is cancelled — the
    /// stream is then dropped without ever finishing. This is the case that
    /// would silently pin the indicator on.
    @MainActor
    func testAbandonedStreamBalancesTheCounter() async throws {
        try await waitForIdle()

        let upstream = makeStream { continuation in
            for index in 0..<1000 {
                continuation.yield("chunk \(index)")
            }
            continuation.finish()
        }

        for try await _ in LLMRouter.monitored(upstream) {
            break // walk away after the first delta, like a cancelled preview
        }

        try await waitForIdle()
        XCTAssertFalse(AIActivityMonitor.shared.isActive, "abandoning a stream must not leave the indicator lit")
    }
}
