import AppKit
import SwiftUI
import XCTest
@testable import Tippi

/// Absturz 2026-10-07 (Michael, jedes Diktat in eine Tippi-Notiz): AppKit brach mit
/// „more Update Constraints in Window passes than there are views in the window“ ab.
/// Fenster laut Systemprotokoll bei allen fünf Abstürzen 228 × 71 und dem Mauszeiger
/// folgend = der Toast. Im Stack: SwiftUI passt die Fenstergröße selbst an
/// (`updateAnimatedWindowSize`) gegen Tippis eigenes `setFrame` → Schleife.
/// 2.23.1 schaltete nur die Größenautomatik ab — stürzte weiter ab. Debug-Prüfstand
/// (`TIPPI_REPRO_NOTES_DICTATION`) stürzte 2 von 2 Läufen an der Anzeige (220 × 80) ab,
/// Stack `updateWindowContentSizeExtremaIfNecessary`: das macht der Hosting-View nur als
/// `contentView`. Fix: Hosting-View in einem schlichten Container, feste Größe.
@MainActor
final class ToastLayoutLoopTests: XCTestCase {
    func testFixedSizeContentWrapsHostingViewAndDisablesAutosizing() throws {
        let (content, size) = NSHostingView<AnyView>.fixedSizeContent(
            AnyView(Text("Eingefügt · Parakeet v3").padding(18)))
        XCTAssertFalse(content is NSHostingView<AnyView>, "Hosting-View darf nicht selbst Fensterinhalt sein")
        let host = try XCTUnwrap(content.subviews.first as? NSHostingView<AnyView>)
        XCTAssertEqual(host.frame, content.bounds, "Hosting-View füllt den Container genau aus")
        XCTAssertEqual(content.frame.size, size)
        XCTAssertTrue(host.autoresizingMask.contains([.width, .height]))
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
        XCTAssertFalse(window.contentView is NSHostingView<AnyView>)
        XCTAssertNotNil(window.contentView?.subviews.first as? NSHostingView<AnyView>)
        XCTAssertGreaterThan(window.frame.width, 50)
    }

    func testRecordingIndicatorUsesFixedSizeContent() throws {
        let recorder = AudioRecorder()
        RecordingIndicatorWindowController.shared.show(mode: .transcribing, recorder: recorder, aiEnabled: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let window = try XCTUnwrap(RecordingIndicatorWindowController.shared.windowForTesting)
        XCTAssertFalse(window.contentView is NSHostingView<AnyView>)
        XCTAssertNotNil(window.contentView?.subviews.first as? NSHostingView<AnyView>)
        XCTAssertGreaterThan(window.frame.width, 50)
        RecordingIndicatorWindowController.shared.hide()
    }
}
