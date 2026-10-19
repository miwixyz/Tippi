import XCTest
@testable import Tippi

/// Pause (Michael, 2026-10-19): nur das Automatische, Endzeitpunkt übersteht einen Neustart.
final class TippiPauseTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "tippi.tests.pause"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNotPausedByDefault() {
        XCTAssertFalse(TippiPause.isActive(defaults))
        XCTAssertNil(TippiPause.pausedUntil(defaults))
    }

    func testPauseEndsByItself() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        TippiPause.pause(until: TippiPause.end(for: .minutes15, now: now), defaults)
        XCTAssertTrue(TippiPause.isActive(now: now.addingTimeInterval(14 * 60), defaults))
        XCTAssertFalse(TippiPause.isActive(now: now.addingTimeInterval(15 * 60 + 1), defaults))
    }

    func testResumeEndsPause() {
        TippiPause.pause(until: TippiPause.end(for: .untilResumed, now: Date()), defaults)
        XCTAssertTrue(TippiPause.isActive(defaults))
        TippiPause.resume(defaults)
        XCTAssertFalse(TippiPause.isActive(defaults))
    }

    func testUntilTomorrowIsSixInTheMorning() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 22, minute: 30))!
        let end = TippiPause.end(for: .untilTomorrow, now: evening, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: end), DateComponents(day: 20, hour: 6, minute: 0))
    }

    func testOneHour() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TippiPause.end(for: .hour1, now: now).timeIntervalSince(now), 3600)
    }
}
