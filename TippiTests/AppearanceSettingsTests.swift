import AppKit
import XCTest
@testable import Tippi

/// Settings → General → Appearance. Only the mapping is tested here; setting
/// `NSApp.appearance` in the test host would repaint the host, not prove more.
@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private typealias Mode = AppearanceSettings.Mode
    private let suites = ThrowawayDefaults()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    func testModeMapsToAppearanceName() {
        XCTAssertNil(Mode.system.appearanceName, "system = inherit, no override")
        XCTAssertEqual(Mode.light.appearanceName, .aqua)
        XCTAssertEqual(Mode.dark.appearanceName, .darkAqua)
    }

    func testEffectiveDarkFollowsSystemOnlyInSystemMode() {
        XCTAssertTrue(Mode.system.isDark(systemIsDark: true))
        XCTAssertFalse(Mode.system.isDark(systemIsDark: false))
        XCTAssertFalse(Mode.light.isDark(systemIsDark: true))
        XCTAssertFalse(Mode.light.isDark(systemIsDark: false))
        XCTAssertTrue(Mode.dark.isDark(systemIsDark: false))
        XCTAssertTrue(Mode.dark.isDark(systemIsDark: true))
    }

    func testStoredModeDefaultsToSystem() {
        let defaults = suites.make()
        XCTAssertEqual(AppearanceSettings.storedMode(in: defaults), .system)
        defaults.set("sepia", forKey: AppearanceSettings.modeKey)
        XCTAssertEqual(AppearanceSettings.storedMode(in: defaults), .system, "unknown value must not break")
        defaults.set("dark", forKey: AppearanceSettings.modeKey)
        XCTAssertEqual(AppearanceSettings.storedMode(in: defaults), .dark)
        defaults.set("light", forKey: AppearanceSettings.modeKey)
        XCTAssertEqual(AppearanceSettings.storedMode(in: defaults), .light)
    }
}
