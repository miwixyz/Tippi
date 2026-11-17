import XCTest
@testable import Tippi

/// Entladen der lokalen Modelle nach 15 Min ohne Nutzung (Audit-Fund 2,
/// 2026-11-17). Geprüft wird die Entscheidung — ohne Modell, ohne Server,
/// mit eingesetzter Uhr. Einstellungen nur in einer Wegwerf-Suite.
@MainActor
final class LocalModelIdleUnloaderTests: XCTestCase {
    private let suites = ThrowawayDefaults()
    private var savedStore: UserDefaults!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        savedStore = LocalModelIdleUnloader.store
        LocalModelIdleUnloader.store = suites.make()
    }

    override func tearDown() {
        LocalModelIdleUnloader.store = savedStore
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Reine Entscheidung

    func testNeverUsedKeepsWithoutTimer() {
        XCTAssertEqual(LocalModelIdleUnloader.decide(enabled: true, lastUse: nil, now: start, busy: false), .keep)
    }

    func testSwitchedOffNeverUnloads() {
        let longAgo = start.addingTimeInterval(-3600)
        XCTAssertEqual(LocalModelIdleUnloader.decide(enabled: false, lastUse: longAgo, now: start, busy: false), .keep)
    }

    func testBeforeTheLimitWaitsForTheRest() {
        let used = start.addingTimeInterval(-10 * 60)
        XCTAssertEqual(LocalModelIdleUnloader.decide(enabled: true, lastUse: used, now: start, busy: false),
                       .wait(5 * 60))
    }

    func testAfterTheLimitUnloads() {
        let used = start.addingTimeInterval(-15 * 60)
        XCTAssertEqual(LocalModelIdleUnloader.decide(enabled: true, lastUse: used, now: start, busy: false), .unload)
    }

    func testBusyAtTheLimitChecksAgainLaterInsteadOfUnloading() {
        let used = start.addingTimeInterval(-20 * 60)
        XCTAssertEqual(LocalModelIdleUnloader.decide(enabled: true, lastUse: used, now: start, busy: true),
                       .wait(LocalModelIdleUnloader.busyRecheck))
    }

    func testDefaultIsOn() {
        XCTAssertTrue(LocalModelIdleUnloader.isEnabled)
        LocalModelIdleUnloader.isEnabled = false
        XCTAssertFalse(LocalModelIdleUnloader.isEnabled)
    }

    // MARK: - Ablauf mit eingesetzter Uhr

    private func makeUnloader(clock: @escaping () -> Date, onUnload: @escaping () -> Void) -> LocalModelIdleUnloader {
        let unloader = LocalModelIdleUnloader()
        unloader.now = clock
        unloader.unload = onUnload
        return unloader
    }

    func testUseResetsTheClock() {
        var now = start
        var unloads = 0
        let unloader = makeUnloader(clock: { now }, onUnload: { unloads += 1 })
        unloader.noteUse()
        now = start.addingTimeInterval(14 * 60)
        unloader.noteUse()                       // Nutzung kurz vor Ablauf
        now = start.addingTimeInterval(16 * 60)
        unloader.evaluate()                      // Timer wacht zur alten Frist auf
        XCTAssertEqual(unloads, 0, "Nutzung nach 14 Min verschiebt die Frist auf 29 Min")
        now = start.addingTimeInterval(29 * 60)
        unloader.evaluate()
        XCTAssertEqual(unloads, 1)
        unloader.settingChanged()
    }

    func testRunningRequestBlocksUnloadUntilItEnds() {
        var now = start
        var unloads = 0
        let unloader = makeUnloader(clock: { now }, onUnload: { unloads += 1 })
        unloader.beginRequest()
        now = start.addingTimeInterval(60 * 60)  // eine hängende Anfrage, eine Stunde
        unloader.evaluate()
        XCTAssertEqual(unloads, 0, "Während einer Anfrage wird nie entladen")
        unloader.endRequest()                    // Ende zählt als Nutzung
        now = now.addingTimeInterval(15 * 60)
        unloader.evaluate()
        XCTAssertEqual(unloads, 1)
        unloader.settingChanged()
    }

    func testDictationInProgressBlocksUnload() {
        var now = start
        var unloads = 0
        var dictating = true
        let unloader = makeUnloader(clock: { now }, onUnload: { unloads += 1 })
        unloader.isBusy = { dictating }
        unloader.noteUse()
        now = start.addingTimeInterval(20 * 60)
        unloader.evaluate()
        XCTAssertEqual(unloads, 0)
        dictating = false
        unloader.evaluate()
        XCTAssertEqual(unloads, 1)
    }

    func testUnloadsOnlyOncePerIdlePeriod() {
        var now = start
        var unloads = 0
        let unloader = makeUnloader(clock: { now }, onUnload: { unloads += 1 })
        unloader.noteUse()
        now = start.addingTimeInterval(15 * 60)
        unloader.evaluate()
        unloader.evaluate()
        XCTAssertEqual(unloads, 1, "Nach dem Entladen gibt es bis zur nächsten Nutzung nichts mehr zu tun")
        XCTAssertNil(unloader.lastUse)
    }

    func testSwitchedOffNothingHappens() {
        LocalModelIdleUnloader.isEnabled = false
        var now = start
        var unloads = 0
        let unloader = makeUnloader(clock: { now }, onUnload: { unloads += 1 })
        unloader.noteUse()
        now = start.addingTimeInterval(60 * 60)
        unloader.evaluate()
        XCTAssertEqual(unloads, 0)
    }

    // MARK: - Server: nur den eigenen stoppen

    func testStopIfOwnedLeavesAServerItDidNotStartAlone() {
        // Ohne eigenen Prozess (frischer Zustand) stoppt der Leerlauf nichts.
        let manager = MLXServerManager()
        XCTAssertFalse(manager.stopIfOwned())
        XCTAssertFalse(manager.unloadedForIdle, "Nichts gestoppt → Statusanzeige bleibt bei „gestoppt“")
    }
}
