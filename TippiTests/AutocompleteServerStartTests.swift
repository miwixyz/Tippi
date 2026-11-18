import XCTest
@testable import Tippi

/// Regression aus 7bda155 (17.11.): Nach dem App-Start ist der MLX-Server `.stopped`, aber nicht
/// „wegen Leerlauf entladen“ → die Autovervollständigung startete ihn nie, es kamen keine
/// Vorschläge. Ein von Hand gestoppter Server soll trotzdem gestoppt bleiben.
@MainActor
final class AutocompleteServerStartTests: XCTestCase {

    func testStartsAfterAppLaunch() {
        let manager = MLXServerManager()   // frischer Zustand wie nach dem Start von Tippi
        XCTAssertTrue(AutocompleteController.shouldStartOwnServer(manager, installed: true))
    }

    func testStaysStoppedAfterUserStop() {
        let manager = MLXServerManager()
        manager.stop(byUser: true)
        XCTAssertFalse(AutocompleteController.shouldStartOwnServer(manager, installed: true))
    }

    func testNeverWithoutInstallation() {
        XCTAssertFalse(AutocompleteController.shouldStartOwnServer(MLXServerManager(), installed: false))
    }
}
