import AppKit
import ApplicationServices
import IOKit
import IOKit.hid

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = checkInputMonitoring()
    }

    /// Triggers macOS's native Accessibility consent prompt the first time it is called,
    /// otherwise no-op. The user must still flip the toggle in System Settings.
    func requestAccessibilityPrompt() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue!] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Triggers the Input Monitoring TCC prompt on the first call.
    /// On subsequent calls (after the user has decided), returns immediately.
    func requestInputMonitoringPrompt() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )!
        NSWorkspace.shared.open(url)
    }

    /// Probe the actual capability rather than just asking TCC.
    /// `IOHIDCheckAccess` can return "denied" even when `CGEvent.tapCreate` succeeds —
    /// especially for ad-hoc signed binaries right after permission was flipped.
    private func checkInputMonitoring() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            // Real fallback: maybe TCC says yes even if tap creation fails
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
        // Tap created — Input Monitoring works. Clean up immediately.
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }
}
