import AppKit
import XCTest
@testable import Tippi

/// Code-Audit 18.11.: Das Einstellungsfenster wird beim Schließen nur versteckt, `onDisappear` feuert
/// nicht. Ein aufnehmender Tastenrekorder behielt so seinen Monitor, und die nächste ⌘-Kombination in
/// einem anderen Tippi-Fenster (z. B. ⌘V in den Notizen) wurde als globales Kürzel gespeichert.
@MainActor
final class RecorderMonitorStoreTests: XCTestCase {

    override func tearDown() {
        RecorderMonitorStore.release()
        super.tearDown()
    }

    func testClosingTheWindowReleasesTheMonitor() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let token = RecorderMonitorStore.releaseOnClose(of: window)
        defer { NotificationCenter.default.removeObserver(token) }
        RecorderMonitorStore.active = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { $0 }

        window.close()

        XCTAssertNil(RecorderMonitorStore.active, "monitor must not outlive the closed settings window")
    }

    func testReleaseTellsTheFieldsSoTheyStopShowingRecording() {
        RecorderMonitorStore.active = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { $0 }
        let posted = expectation(forNotification: RecorderMonitorStore.didRelease, object: nil)
        RecorderMonitorStore.release()
        wait(for: [posted], timeout: 1)
    }

    func testOtherWindowsDoNotRelease() {
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let other = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        settings.isReleasedWhenClosed = false
        other.isReleasedWhenClosed = false
        let token = RecorderMonitorStore.releaseOnClose(of: settings)
        defer { NotificationCenter.default.removeObserver(token) }
        RecorderMonitorStore.active = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { $0 }

        other.close()

        XCTAssertNotNil(RecorderMonitorStore.active)
    }
}
