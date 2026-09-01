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
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording: Bool = false
    /// Linear amplitude 0…1 for waveform UI (updated at ~10 Hz while recording).
    @Published private(set) var level: Float = 0

    private var recorder: AVAudioRecorder?
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
    func start() throws -> URL {
        // Re-entrancy guard: this single instance is shared by dictation, the
        // popup mic and the translate panel, which fire from independent global
        // hotkeys. Starting again while a take is in flight would overwrite
        // recorder/outputURL, orphan the previous WAV (the user's voice) and leak
        // the still-running recorder. Finalize the previous take first.
        if isRecording {
            NSLog("Tippi: AudioRecorder.start() called while already recording — finalizing previous take first")
            _ = stop()
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tippi-voice-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey:          Int(kAudioFormatLinearPCM),
            AVSampleRateKey:        16_000,
            AVNumberOfChannelsKey:  1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey:  false,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true
            guard rec.record() else {
                throw AudioRecorderError.setupFailed("AVAudioRecorder.record() returned false")
            }
            recorder = rec
            outputURL = url
            isRecording = true
            startLevelTimer()
            muteSystemAudioIfEnabled()
            return url
        } catch let err as AudioRecorderError {
            throw err
        } catch {
            throw AudioRecorderError.setupFailed(error.localizedDescription)
        }
    }

    /// Stops recording and returns the completed WAV file URL.
    @discardableResult
    func stop() -> URL? {
        stopLevelTimer()
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        restoreSystemAudioIfNeeded()
        // Hand the URL over and forget it — otherwise a stop() without a
        // following transcription (which owns the cleanup `defer`) would leave
        // the temp WAV behind, and a stale URL could be returned twice.
        let url = outputURL
        outputURL = nil
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
        guard let previous = SystemAudioMuter.isMuted() else { return }
        guard SystemAudioMuter.setMuted(true) else { return }
        mutedSystemAudioPreviousState = previous
        UserDefaults.standard.set(previous, forKey: Self.pendingRestoreKey)
    }

    /// Restores system audio to whatever it was before `muteSystemAudioIfEnabled()`
    /// muted it — regardless of the setting's *current* value, so flipping
    /// the toggle off mid-recording can't leave the system stuck muted.
    private func restoreSystemAudioIfNeeded() {
        guard let previous = mutedSystemAudioPreviousState else { return }
        mutedSystemAudioPreviousState = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingRestoreKey)
        SystemAudioMuter.setMuted(previous)
    }

    // MARK: - Level metering

    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                rec.updateMeters()
                let dB = rec.averagePower(forChannel: 0) // -160…0
                let clamped = max(-60, dB)
                self.level = Float((clamped + 60) / 60)
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            // Only act if this error belongs to the currently active recorder —
            // a fast restart would otherwise be aborted by a stale delegate call
            // for the previous recording.
            guard self.recorder === recorder else { return }
            NSLog("Tippi AudioRecorder encode error: \(error?.localizedDescription ?? "?")")
            self.stop()
        }
    }
}
