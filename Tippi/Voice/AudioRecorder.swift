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
        return outputURL
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
            NSLog("Tippi AudioRecorder encode error: \(error?.localizedDescription ?? "?")")
            self.stop()
        }
    }
}
