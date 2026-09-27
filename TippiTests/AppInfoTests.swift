import XCTest
@testable import Tippi

/// App-Liste in den Einstellungen: Name statt Bundle-ID, Rückfall für nicht
/// installierte Apps (die Voreinstellungen enthalten Apps, die nicht jeder hat).
final class AppInfoTests: XCTestCase {
    func testInstalledAppShowsNameNotBundleID() {
        let app = AppInfo(bundleID: "com.apple.Terminal")
        XCTAssertTrue(app.isInstalled)
        XCTAssertEqual(app.name, "Terminal")
        XCTAssertFalse(app.name.hasSuffix(".app"))
    }

    func testUnknownAppFallsBackToBundleID() {
        let app = AppInfo(bundleID: "com.example.not-installed-\(UUID().uuidString)")
        XCTAssertFalse(app.isInstalled)
        XCTAssertEqual(app.name, app.bundleID)
        XCTAssertEqual(app.icon.size, NSSize(width: 16, height: 16))
    }
}
