import AppKit
import SwiftUI
import XCTest
@testable import Tippi

/// Absturz 2026-10-07 (Michael, jedes Diktat in eine Tippi-Notiz): AppKit brach mit
/// „more Update Constraints in Window passes than there are views in the window“ ab.
/// Fenster laut Systemprotokoll bei allen fünf Abstürzen 228 × 71 und dem Mauszeiger
/// folgend = der Toast. Im Stack: SwiftUI passt die Fenstergröße selbst an
/// (`updateAnimatedWindowSize`) gegen Tippis eigenes `setFrame` → Schleife.
/// Fix: Fenster mit fester, getrennt gemessener Größe, ohne SwiftUI-Größenautomatik.
@MainActor
final class ToastLayoutLoopTests: XCTestCase {
    func testFixedSizeHostingViewMeasuresContentAndDisablesAutosizing() {
        let (host, size) = NSHostingView<AnyView>.fixedSizeHost(
            AnyView(Text("Eingefügt · Parakeet v3").padding(18)))
        XCTAssertTrue(host.sizingOptions.isEmpty, "SwiftUI darf die Fenstergröße nicht selbst ändern")
        XCTAssertTrue(host.safeAreaRegions.isEmpty, "Randabstände dürfen nicht auf die Größe zurückwirken")
        XCTAssertGreaterThan(size.width, 50)
        XCTAssertGreaterThan(size.height, 20)
    }

    func testToastWindowKeepsTheSizeTippiSets() throws {
        NSApp.activate(ignoringOtherApps: true)
        ToastWindowController.shared.show(message: "Eingefügt · Parakeet v3")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let window = try XCTUnwrap(ToastWindowController.shared.windowForTesting)
        let host = try XCTUnwrap(window.contentView as? NSHostingView<AnyView>)
        XCTAssertTrue(host.sizingOptions.isEmpty)
        XCTAssertGreaterThan(window.frame.width, 50)
    }

    func testRecordingIndicatorUsesFixedSizeHost() throws {
        let recorder = AudioRecorder()
        RecordingIndicatorWindowController.shared.show(mode: .transcribing, recorder: recorder, aiEnabled: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let window = try XCTUnwrap(RecordingIndicatorWindowController.shared.windowForTesting)
        let host = try XCTUnwrap(window.contentView as? NSHostingView<AnyView>)
        XCTAssertTrue(host.sizingOptions.isEmpty)
        XCTAssertGreaterThan(window.frame.width, 50)
        RecordingIndicatorWindowController.shared.hide()
    }
}
