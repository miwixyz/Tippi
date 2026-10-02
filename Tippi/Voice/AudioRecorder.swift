import CoreAudio
import AVFoundation

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:   return "Microphone access denied."
        case .setupFailed(let m): return "Audio setup failed: \(m)"
        }
    }
}

/// Records microphone audio to a 16 kHz mono WAV file (Whisper's required format).
/// Owned by AppDelegate; the PromptPopup borrows a reference.
///
/// Since 2026-10-02 built on `AVAudioEngine` instead of `AVAudioRecorder`: a tap
/// converts every input buffer to 16 kHz mono and collects it in memory
/// (`SampleStore`); the WAV is written once, in `stop()`, at the URL `start()`
/// already handed out. Same file format as before. Side effect for privacy: the
/// voice is no longer on disk *during* the take, and a crash leaves no partial
/// file. Building blocks + rationale: `AudioCapture.swift`.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording: Bool = false
    /// Linear amplitude 0…1 for waveform UI (updated at ~10 Hz while recording).
    @Published private(set) var level: Float = 0
    /// Length of the take so far, counted in recorded samples — a wall-clock
    /// stopwatch would drift away from the file whenever the audio stack stalls.
    @Published private(set) var elapsed: TimeInterval = 0

    private var engine: AVAudioEngine?
    private var store = SampleStore()
    private var configObserver: NSObjectProtocol?
    private var levelTimer: Timer?
    private var outputURL: URL?

    // MARK: - System audio muting (opt-in)

    private static let muteSystemAudioKey = "recording.muteSystemAudio"
    /// Persisted mirror of `mutedSystemAudioPreviousState`, written right
    /// before muting and cleared right after restoring. Lets `recoverFromCrashIfNeeded()`
    /// detect and fix a system audio left muted by a crash/force-quit
    /// mid-recording — the in-memory flag alone can't survive that.
    private static let pendingRestoreKey = "recording.muteSystemAudio.pendingRestore"

    /// Whether Tippi should mute the default system audio output while
    /// recording (dictation, popup mic, translate panel — all share this
    /// recorder). Default OFF: muting system audio is a convenience for
    /// people who dictate over music/video, not something everyone wants.
    static var muteSystemAudioDuringRecording: Bool {
        get { UserDefaults.standard.bool(forKey: muteSystemAudioKey) }
        set { UserDefaults.standard.set(newValue, forKey: muteSystemAudioKey) }
    }

    /// System output's mute state captured right before we muted it, so
    /// `stop()` restores the *previous* state instead of force-unmuting —
    /// if the user had already muted their speakers themselves, Tippi
    /// shouldn't undo that. `nil` means "we didn't touch system audio for
    /// the current/last take" (setting was off, or the device has no mute
    /// control) — `stop()` uses this as the sole signal for whether to
    /// restore, independent of the *current* value of the setting above,
    /// so toggling the setting off mid-recording can't leave audio muted.
    private var mutedSystemAudioPreviousState: Bool?
    /// The device that was muted — restored explicitly, see `SystemAudioMuter`.
    private var mutedDevice: AudioDeviceID?

    // MARK: - Permission

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Requests microphone permission if undetermined; returns whether access is granted.
    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:          return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:          return false
        }
    }

    // MARK: - Recording

    /// Starts recording. Returns the URL of the temp WAV file that will be written.
    @discardableResult
    func start(owner: Owner) throws -> URL {
        // Re-entrancy guard: this single instance is shared by dictation, the
        // popup mic and the translate panel, which fire from independent global
        // hotkeys. Starting again while a take is in flight would overwrite
        // recorder/outputURL, orphan the previous WAV (the user's voice) and leak
        // the still-running recorder. Finalize the previous take first.
        if isRecording {
            // Finalized, not deleted: the other owner still holds this URL and
            // transcribes what was recorded so far.
            NSLog("Tippi: AudioRecorder.start() called while already recording — finalizing previous take first")
            _ = stop()
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tippi-voice-\(UUID().uuidString).wav")

        let store = SampleStore()
        let engine = AVAudioEngine()
        do {
            try Self.installTap(on: engine, into: store)
            engine.prepare()
            try engine.start()
        } catch let err as AudioRecorderError {
            engine.inputNode.removeTap(onBus: 0)
            throw err
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.setupFailed(error.localizedDescription)
        }
        self.engine = engine
        self.store = store
        observeConfigurationChanges(of: engine)
        outputURL = url
        isRecording = true
        elapsed = 0
        startLevelTimer()
        muteSystemAudioIfEnabled()
        self.owner = owner
        return url
    }

    /// Installs the conversion tap for the input node's *current* format.
    /// `nonisolated` on purpose: the block runs on the audio render thread and
    /// must not be inferred as main-actor code (see scripts/concurrency-lint.sh,
    /// 2.11.5 crash). It only touches `store` (locked) and its own resampler.
    nonisolated private static func installTap(on engine: AVAudioEngine, into store: SampleStore) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A tap whose format differs from the hardware makes AVAudioEngine raise an
        // Objective-C exception — Swift can't catch it, the take is left half-dead
        // (measured 2026-10-02: AirPods mid-take, hardware already 24 kHz, client
        // still 48 kHz → "Format mismatch", pill stuck). Check first, throw a Swift error.
        guard AudioCapture.formatsMatch(hardware: input.inputFormat(forBus: 0), client: format) else {
            throw AudioRecorderError.setupFailed("input device still switching")
        }
        let resampler = try AudioResampler(inputFormat: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do { store.append(try resampler.convert(buffer)) } catch {
                NSLog("Tippi AudioRecorder: conversion failed — \(error.localizedDescription)")
            }
        }
    }

    /// The input device can change mid-take (AirPods connect, USB mic unplugged).
    /// AVAudioEngine then stops and posts a configuration change.
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAfterConfigurationChange(of: engine) }
        }
    }

    /// Bluetooth needs a moment to switch to its headset mode (log 2026-10-02:
    /// ~4 s until the format settled). Try every 0.4 s for up to 6 s.
    private static let resumeAttempts = 15
    private static let resumeDelay: UInt64 = 400_000_000

    /// Continues the take on the new device with a *fresh* engine (the stopped
    /// one keeps stale formats) and the same sample store, so nothing recorded so
    /// far is lost. If the device never settles, the take keeps what it has and
    /// the user ends it as usual — the level meter stays flat meanwhile; a later
    /// configuration change of the old engine tries again.
    private func resumeAfterConfigurationChange(of changed: AVAudioEngine, attempt: Int = 1) {
        guard isRecording, engine === changed else { return }
        changed.inputNode.removeTap(onBus: 0)
        changed.stop()
        let fresh = AVAudioEngine()
        do {
            try Self.installTap(on: fresh, into: store)
            fresh.prepare()
            try fresh.start()
            engine = fresh
            observeConfigurationChanges(of: fresh)
            NSLog("Tippi AudioRecorder: input changed mid-take — resumed (attempt \(attempt))")
        } catch {
            fresh.inputNode.removeTap(onBus: 0)
            guard attempt < Self.resumeAttempts else {
                store.clearLevel()
                NSLog("Tippi AudioRecorder: input change — gave up after \(attempt) attempts, keeping the take so far")
                return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.resumeDelay)
                self?.resumeAfterConfigurationChange(of: changed, attempt: attempt + 1)
            }
        }
    }

    /// Everything recorded so far, 16 kHz mono — for live transcription in the
    /// recording window. A copy; the take keeps recording.
    func snapshot() -> [Float] { isRecording ? store.snapshot() : [] }

    /// Who started the current take. The recorder is one shared instance —
    /// closing the translate panel must not delete a dictation that is
    /// recording at the same time (review 2026-09-27).
    enum Owner { case dictation, popup, translate }
    private(set) var owner: Owner?

    /// Stops and deletes the recording, if `owner` started it — for every path
    /// that abandons its own take. `_ = stop()` forgot the URL and left the
    /// user's voice in $TMPDIR until the next launch's sweep (audit 2026-09-27).
    func discard(ifStartedBy owner: Owner) {
        guard isRecording, self.owner == owner else { return }
        if let url = stop() { try? FileManager.default.removeItem(at: url) }
    }

    /// Stops recording, writes the WAV and returns its URL. The file is
    /// complete when this returns — callers transcribe it right away
    /// (DictationController uses the URL `start()` returned).
    @discardableResult
    func stop() -> URL? {
        owner = nil
        stopLevelTimer()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)   // no further buffers after this
            engine.stop()
        }
        engine = nil
        isRecording = false
        level = 0
        restoreSystemAudioIfNeeded()
        // Hand the URL over and forget it — otherwise a stop() without a
        // following transcription (which owns the cleanup `defer`) would leave
        // the temp WAV behind, and a stale URL could be returned twice.
        let url = outputURL
        outputURL = nil
        let samples = store.drain()
        if let url {
            do { try AudioCapture.writeWAV(samples, to: url) } catch {
                NSLog("Tippi AudioRecorder: writing the WAV failed — \(error.localizedDescription)")
            }
        }
        return url
    }

    /// Best-effort fix for system audio left muted by a crash/force-quit
    /// while a recording (with the mute-system-audio setting on) was in
    /// flight — the normal restore path in `stop()` never got to run.
    /// Safe to call at app launch, before any recording starts.
    static func recoverFromCrashIfNeeded() {
        guard UserDefaults.standard.object(forKey: pendingRestoreKey) != nil else { return }
        let previous = UserDefaults.standard.bool(forKey: pendingRestoreKey)
        UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        SystemAudioMuter.setMuted(previous)
        NSLog("Tippi: recovered system audio mute state left over from a previous crash/force-quit")
    }

    /// Best-effort sweep of orphaned recordings left by a crash/force-quit.
    /// Safe to call at app launch (no transcription is in flight then).
    static func cleanupOrphanedRecordings() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ) else { return }
        for f in files where f.lastPathComponent.hasPrefix("tippi-voice-")
            && f.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: f)
        }
    }

    // MARK: - System audio muting

    /// Captures the current mute state and mutes system audio, but only if
    /// the setting is on. Failing to read/write (device has no mute
    /// control, or a CoreAudio call fails) leaves `mutedSystemAudioPreviousState`
    /// `nil` — `restoreSystemAudioIfNeeded()` then knows there's nothing to
    /// undo, matching the "best-effort, never blocks recording" contract.
    private func muteSystemAudioIfEnabled() {
        guard Self.muteSystemAudioDuringRecording else { return }
        guard let device = SystemAudioMuter.defaultOutputDevice(),
              let previous = SystemAudioMuter.isMuted(device: device) else { return }
        guard SystemAudioMuter.setMuted(true, device: device) else { return }
        mutedSystemAudioPreviousState = previous
        mutedDevice = device
        UserDefaults.standard.set(previous, forKey: Self.pendingRestoreKey)
    }

    /// Restores system audio to whatever it was before `muteSystemAudioIfEnabled()`
    /// muted it — regardless of the setting's *current* value, so flipping
    /// the toggle off mid-recording can't leave the system stuck muted.
    private func restoreSystemAudioIfNeeded() {
        guard let previous = mutedSystemAudioPreviousState else { return }
        mutedSystemAudioPreviousState = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingRestoreKey)
        if let device = mutedDevice {
            SystemAudioMuter.setMuted(previous, device: device)
        } else {
            SystemAudioMuter.setMuted(previous)
        }
        mutedDevice = nil
    }

    // MARK: - Level metering

    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.level = self.store.level
                self.elapsed = Double(self.store.count) / AudioCapture.sampleRate
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
