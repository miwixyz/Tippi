import AppKit
import Combine
import Security

/// Gnotchi – the family's notch app (github.com/miwixyz/Gnotchi) – shows Tippi's dictation in the notch
/// from Gnotchi 0.2.0 on. While it does, Tippi hides its own recording pill.
///
/// Protocol (Gnotchi SECURE-DESIGN G17): `DistributedNotificationCenter`, name `com.tippi.app.aufnahme`,
/// `userInfo = ["v": 1, "state": "recording"|"transcribing"|"idle", "level": 0…1]`. 10 Hz while recording,
/// 1 Hz heartbeat while transcribing, one `idle` at the end. **Never text** – any local process can read
/// distributed notifications, so they only reveal *that* the user dictates.
///
/// Tippi hides its pill only if a running `dev.mwlr.gnotchi` is signed by the same team (code signature
/// checked via PID, not trusted by bundle id), is at least 0.2.0, and its switch `tippiRecording` is not off.
/// With the live transcription preview on, the text goes to Gnotchi 0.3.0+ over a separate, verified local
/// socket (`GnotchiLiveText`); if that link is not up, Tippi keeps its own pill.
enum GnotchiBridge {

    enum State: String { case recording, transcribing, idle }

    static let bundleID = "dev.mwlr.gnotchi"
    static let notification = Notification.Name("com.tippi.app.aufnahme")
    /// Same requirement Gnotchi uses for itself (Gnotchi BundleIntegrity.appRequirement).
    static let requirement =
        #"anchor apple generic and identifier "dev.mwlr.gnotchi" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
    static let minimumVersion = [0, 2, 0]
    static let settingKey = "tippiRecording"

    // MARK: Pure parts (tested)

    static func payload(_ state: State, level: Float?) -> [String: Any] {
        var p: [String: Any] = ["v": 1, "state": state.rawValue]
        if let level {
            let v = Double(level)
            // Explicit Double: in an `Any` context Swift would store the literal `0` as Int.
            let clamped: Double = v.isFinite ? min(max(v, 0), 1) : 0
            p["level"] = clamped
        }
        return p
    }

    static func versionSupported(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return false }
        let nums = parts.compactMap { $0 }
        for i in 0..<max(nums.count, minimumVersion.count) {
            let a = i < nums.count ? nums[i] : 0
            let b = i < minimumVersion.count ? minimumVersion[i] : 0
            if a != b { return a > b }
        }
        return true
    }

    /// Missing key = Gnotchi's factory default (on). Only an explicit `false` turns it off.
    static func settingAllows(_ value: Any?) -> Bool {
        (value as? Bool) ?? true
    }

    // MARK: System

    /// Checked once at the start of each dictation (a few ms). If Gnotchi quits mid-dictation, that
    /// dictation shows no indicator – the system's orange microphone dot remains.
    @MainActor
    static func gnotchiShowsDictation() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) else { return false }
        let version = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        guard versionSupported(version), isSignedByTeam(pid: app.processIdentifier) else { return false }
        let value = CFPreferencesCopyAppValue(settingKey as CFString, bundleID as CFString)
        return settingAllows(value)
    }

    private static func isSignedByTeam(pid: pid_t) -> Bool {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}

/// Shows dictation either in Tippi's own pill or – if Gnotchi takes over (decided once per dictation) –
/// by broadcasting the state to Gnotchi. One call per state keeps DictationController short.
@MainActor
final class DictationIndicator {
    private var notchActive = false
    private let gnotchi = GnotchiBroadcaster()
    /// Live-preview text to Gnotchi (0.3.0), only while a verified link is up.
    private var liveLink: GnotchiLiveLink?
    private var textSubscription: AnyCancellable?

    func recording(recorder: AudioRecorder, preview: LiveTranscriptionPreview?, aiEnabled: Bool, source: DictationSource) {
        closeLiveLink()
        let ready = GnotchiBridge.gnotchiShowsDictation()
        if ready, preview != nil { liveLink = GnotchiLiveLink.open() }
        let mode = GnotchiLiveText.indicatorMode(livePreview: preview != nil, gnotchiReady: ready,
                                                 liveLinkReady: liveLink != nil)
        notchActive = mode != .tippiPill
        if notchActive {
            gnotchi.recording(recorder: recorder)
            if let preview, let link = liveLink {
                textSubscription = preview.$text.removeDuplicates().sink { [weak link] text in link?.send(text) }
            }
        } else {
            closeLiveLink()
            RecordingIndicatorWindowController.shared.show(mode: .recording, recorder: recorder, preview: preview,
                                                           aiEnabled: aiEnabled, source: source)
        }
    }

    /// Also used when the AI polish starts (then with the provider name for Tippi's pill).
    func transcribing(recorder: AudioRecorder, aiEnabled: Bool, providerName: String? = nil, source: DictationSource) {
        if notchActive {
            gnotchi.transcribing()
        } else {
            RecordingIndicatorWindowController.shared.show(mode: .transcribing, recorder: recorder, aiEnabled: aiEnabled,
                                                           providerName: providerName, source: source)
        }
    }

    func idle() {
        closeLiveLink()
        guard notchActive else { return }
        notchActive = false
        gnotchi.idle()
    }

    private func closeLiveLink() {
        textSubscription = nil
        liveLink?.close()
        liveLink = nil
    }
}

/// Sends the dictation state to Gnotchi. Timers run on the main run loop.
@MainActor
final class GnotchiBroadcaster {
    private var timer: Timer?

    func recording(recorder: AudioRecorder) {
        timer?.invalidate()
        post(.recording, level: recorder.level)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak recorder] _ in
            Task { @MainActor in self?.post(.recording, level: recorder?.level ?? 0) }
        }
    }

    func transcribing() {
        timer?.invalidate()
        post(.transcribing, level: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.post(.transcribing, level: nil) }
        }
    }

    func idle() {
        timer?.invalidate()
        timer = nil
        post(.idle, level: nil)
    }

    private func post(_ state: GnotchiBridge.State, level: Float?) {
        DistributedNotificationCenter.default().postNotificationName(
            GnotchiBridge.notification, object: nil,
            userInfo: GnotchiBridge.payload(state, level: level), deliverImmediately: true)
    }
}
