import AppKit

// MARK: - Settings

/// Persisted dictation settings. The feature is off by default and only
/// activatable once a Whisper model is configured (`WhisperConfig.isConfigured`).
@MainActor
enum DictationSettings {
    private static let enabledKey = "dictation.enabled"
    private static let comboKey   = "dictation.hotkeyCombo.v1"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var combo: KeyCombo {
        get {
            guard let data = UserDefaults.standard.data(forKey: comboKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else {
                return .dictationDefault
            }
            return combo
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: comboKey)
            }
        }
    }
}

// MARK: - Controller

/// Dictation-mode state machine. Press the dictation hot key once to start
/// recording, again to stop → transcribe → insert at the caret. No popup is
/// shown, so the source app keeps focus and the caret stays put.
@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(URL)
        case transcribing
    }

    @Published private(set) var state: State = .idle

    private let recorder = AudioRecorder()

    /// Toggles dictation. `targetApp` is the app that was frontmost when the
    /// hot key fired — used as the AX target for insertion.
    func toggle(targetApp: NSRunningApplication?) async {
        switch state {
        case .idle:
            await start()
        case .recording(let url):
            await stopAndInsert(wavURL: url, targetApp: targetApp)
        case .transcribing:
            // Ignore the toggle while a transcription is still running.
            NSLog("Tippi: dictation toggle ignored — transcribing")
        }
    }

    // MARK: - Private

    private func start() async {
        guard await AudioRecorder.requestPermission() else {
            ToastWindowController.shared.show(message: String(localized: "dictation.toast.micDenied"))
            return
        }
        do {
            let url = try recorder.start()
            state = .recording(url)
            RecordingIndicatorWindowController.shared.show(mode: .recording)
            NSLog("Tippi: dictation recording started")
        } catch {
            ToastWindowController.shared.show(message: error.localizedDescription)
            NSLog("Tippi: dictation start failed — \(error.localizedDescription)")
        }
    }

    private func stopAndInsert(wavURL: URL, targetApp: NSRunningApplication?) async {
        recorder.stop()
        state = .transcribing
        RecordingIndicatorWindowController.shared.show(mode: .transcribing)

        do {
            let text = try await WhisperTranscriber.transcribe(wavURL: wavURL)
            await TextInsertion.replace(with: text, in: targetApp)
            RecordingIndicatorWindowController.shared.hide()
            ToastWindowController.shared.show(message: String(localized: "dictation.toast.inserted"))
            NSLog("Tippi: dictation inserted \(text.count) chars")
        } catch {
            RecordingIndicatorWindowController.shared.hide()
            ToastWindowController.shared.show(message: error.localizedDescription)
            NSLog("Tippi: dictation transcription failed — \(error.localizedDescription)")
        }

        state = .idle
    }
}
