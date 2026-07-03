import SwiftUI

/// Spotlight-style "type text, get translation" view. Auto-detects German ⇄
/// Spanish and translates to the other one — no language picker. Type or
/// speak the input (mic button), read or hear the result (speaker button).
/// Result is shown for manual copy only (⌘C or the Copy button); nothing is
/// inserted or copied automatically.
struct TranslateQuickView: View {
    let onClose: () -> Void
    /// Shared recorder (same instance dictation uses) for the mic button.
    /// nil disables voice input (e.g. if wiring is unavailable).
    let audioRecorder: AudioRecorder?

    @State private var input = ""
    @State private var state: ViewState = .idle
    @State private var voice: VoiceState = .idle
    @State private var task: Task<Void, Never>?
    @State private var transcriptionTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool
    @ObservedObject private var speech = TranslateSpeech.shared

    enum ViewState: Equatable {
        case idle
        case loading
        case result(text: String, providerDisplay: String)
        case failed(message: String)
    }

    enum VoiceState: Equatable {
        case idle
        case recording
        case transcribing
    }

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            if state != .idle {
                Divider()
                resultArea
            }
            Spacer(minLength: 0)
        }
        .frame(width: 560, height: 260, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(1) // keeps the stroke from clipping against the panel edge
        .onAppear {
            // Focus the field once the panel has actually become key window.
            // Setting @FocusState synchronously in onAppear fires before the
            // borderless NSPanel finishes becoming key, so the focus silently
            // drops. A short hop to the next runloop turn (after
            // makeKeyAndOrderFront settles) makes it stick reliably.
            inputFocused = true
            DispatchQueue.main.async { inputFocused = true }
        }
        .onExitCommand { onClose() }
        .onDisappear {
            task?.cancel()
            transcriptionTask?.cancel()
            if audioRecorder?.isRecording == true { _ = audioRecorder?.stop() }
            speech.stop()
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.bubble")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            TextField(String(localized: "translate.panel.placeholder"), text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($inputFocused)
                .onSubmit { translate() }

            if state == .loading || voice == .transcribing {
                ProgressView()
                    .controlSize(.small)
            }

            micButton
            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var micButton: some View {
        if audioRecorder != nil {
            Button(action: toggleRecording) {
                Image(systemName: voice == .recording ? "mic.fill" : "mic")
                    .font(.system(size: 16))
                    .foregroundStyle(voice == .recording ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(voice == .transcribing)
            .help(String(localized: "translate.panel.mic"))
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "translate.panel.close"))
    }

    // MARK: - Result area

    @ViewBuilder
    private var resultArea: some View {
        switch state {
        case .idle:
            EmptyView()

        case .loading:
            HStack {
                Text(String(localized: "translate.panel.translating"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)

        case .result(let text, let providerDisplay):
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.system(size: 16))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(providerDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        speech.toggle(text)
                    } label: {
                        Label(
                            speech.isSpeaking
                                ? String(localized: "translate.panel.stop")
                                : String(localized: "translate.panel.speak"),
                            systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        copy(text)
                    } label: {
                        Label(String(localized: "translate.panel.copy"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("c", modifiers: .command)
                }
            }
            .padding(16)

        case .failed(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)
        }
    }

    // MARK: - Translate

    private func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        state = .loading
        task = Task {
            do {
                let result = try await LLMRouter.shared.complete(
                    systemPrompt: TranslateSettings.systemPrompt,
                    userText: text
                )
                guard !Task.isCancelled else { return }
                state = .result(text: result.text, providerDisplay: result.providerDisplay)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Voice input

    private func toggleRecording() {
        switch voice {
        case .idle:        startRecording()
        case .recording:   stopAndTranscribe()
        case .transcribing: break
        }
    }

    private func startRecording() {
        guard let rec = audioRecorder else { return }
        Task {
            guard await AudioRecorder.requestPermission() else {
                state = .failed(message: String(localized: "translate.panel.micDenied"))
                return
            }
            do {
                _ = try rec.start()
                voice = .recording
                SpeechTranscriber.prewarm()
            } catch {
                voice = .idle
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    private func stopAndTranscribe() {
        guard let wavURL = audioRecorder?.stop() else {
            voice = .idle
            return
        }
        voice = .transcribing
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            do {
                let text = try await SpeechTranscriber.transcribe(wavURL: wavURL)
                guard !Task.isCancelled else { return }
                voice = .idle
                input = text
                // Speaking straight into a translation is the natural intent —
                // auto-translate the transcript so the user doesn't have to
                // press Return after dictating.
                translate()
            } catch {
                guard !Task.isCancelled else { return }
                voice = .idle
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Copy

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
