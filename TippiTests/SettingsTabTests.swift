import XCTest
@testable import Tippi

/// Jeder Einstellungsbereich hat Titel und Symbol — und der Titel ist übersetzt,
/// nicht der rohe Schlüssel (ein vergessener Localizable-Eintrag erschiene sonst
/// als „settings.tab.permissions“ in der Seitenleiste).
final class SettingsTabTests: XCTestCase {
    func testEveryTabHasLocalizedTitleAndSymbol() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "\(tab)")
            XCTAssertFalse(tab.title.hasPrefix("settings.tab."), "Titel nicht übersetzt: \(tab)")
            XCTAssertNotNil(NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil),
                            "SF Symbol fehlt: \(tab.symbol)")
        }
    }

    func testPermissionsTabExists() {
        XCTAssertTrue(SettingsTab.allCases.contains(.permissions))
    }
}
