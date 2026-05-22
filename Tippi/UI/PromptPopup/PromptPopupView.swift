import SwiftUI

// MARK: - Voice Mode

/// Controls how the mic button in the popup behaves.
enum VoiceMode {
    /// No text pre-selected — mic records text to insert (dictation).
    case dictate
    /// Text is pre-selected — mic records a spoken AI instruction.
    case voicePrompt
}

// MARK: - Main View

struct PromptPopupView: View {
    let prompts: [DemoPrompt]
    let onSelect: (DemoPrompt) -> Void
    let onDismiss: () -> Void
    var onDirectInsert: (() -> Void)? = nil
    var audioRecorder: AudioRecorder? = nil
    var onVoiceTranscribed: ((String) -> Void)? = nil
    var voiceMode: VoiceMode = .dictate

    // -1 means the "Direkt einfügen" row is highlighted (only when onDirectInsert != nil)
    @State private var selectedIndex: Int
    @FocusState private var focused: Bool

    init(
        prompts: [DemoPrompt],
        onSelect: @escaping (DemoPrompt) -> Void,
        onDismiss: @escaping () -> Void,
        onDirectInsert: (() -> Void)? = nil,
        audioRecorder: AudioRecorder? = nil,
        onVoiceTranscribed: ((String) -> Void)? = nil,
        voiceMode: VoiceMode = .dictate
    ) {
        self.prompts = prompts
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.onDirectInsert = onDirectInsert
        self.audioRecorder = audioRecorder
        self.onVoiceTranscribed = onVoiceTranscribed
        self.voiceMode = voiceMode
        // Always start at first AI prompt (index 0).
        // "Direkt einfügen" row (index -1) is visible but requires explicit click or ↑ arrow.
        _selectedIndex = State(initialValue: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let insert = onDirectInsert {
                DirectInsertRow(
                    isSelected: selectedIndex == -1,
                    onHover: { selectedIndex = -1 },
                    onTap: insert
                )
                Divider()
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }
            list
            if audioRecorder != nil || !WhisperConfig.isConfigured {
                Divider()
                VoiceSection(
                    audioRecorder: audioRecorder,
                    mode: voiceMode,
                    onTranscribed: onVoiceTranscribed ?? { _ in }
                )
            }
        }
        .frame(width: 290)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            let minIndex = onDirectInsert != nil ? -1 : 0
            selectedIndex = max(minIndex, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(prompts.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex == -1 {
                onDirectInsert?()
            } else {
                onSelect(prompts[selectedIndex])
            }
            return .handled
        }
        .onKeyPress { keyPress in
            guard let first = keyPress.characters.first,
                  let digit = Int(String(first)) else { return .ignored }
            if digit >= 1 && digit <= prompts.count {
                onSelect(prompts[digit - 1])
                return .handled
            }
            return .ignored
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline")
                .foregroundStyle(.tint)
            Text("Tippi")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                PromptRow(
                    prompt: prompt,
                    shortcut: "\(index + 1)",
                    isSelected: index == selectedIndex,
                    onHover: { selectedIndex = index },
                    onTap: { onSelect(prompt) }
                )
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Direct Insert Row

private struct DirectInsertRow: View {
    let isSelected: Bool
    let onHover: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .accentColor)
                Text(String(localized: "voice.directInsert"))
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
                Spacer()
                Text("↩")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.25) : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}

// MARK: - Voice Section

private struct VoiceSection: View {
    var audioRecorder: AudioRecorder?
    let mode: VoiceMode
    let onTranscribed: (String) -> Void

    private enum State { case idle, recording, transcribing, failed(String) }
    @SwiftUI.State private var voiceState: State = .idle
    @SwiftUI.State private var transcriptionTask: Task<Void, Never>?
    @ObservedObject private var recorder: AudioRecorder

    init(audioRecorder: AudioRecorder?, mode: VoiceMode, onTranscribed: @escaping (String) -> Void) {
        self.audioRecorder = audioRecorder
        self.mode          = mode
        self.onTranscribed = onTranscribed
        self._recorder     = ObservedObject(wrappedValue: audioRecorder ?? AudioRecorder())
    }

    var body: some View {
        Group {
            if !WhisperConfig.isConfigured {
                setupBanner
            } else {
                voiceControls
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onDisappear {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            if audioRecorder?.isRecording == true {
                _ = audioRecorder?.stop()
            }
        }
    }

    // MARK: Setup banner

    private var setupBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "voice.setup.banner.title"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(String(localized: "voice.setup.banner.body"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: Voice controls

    @ViewBuilder
    private var voiceControls: some View {
        HStack(spacing: 10) {
            micButton
            statusText
            Spacer()
            if case .recording = voiceState {
                waveform
            }
        }
    }

    private var micButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(micButtonBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: micButtonSymbol)
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .disabled({
            if case .transcribing = voiceState { return true }
            return false
        }())
    }

    private var micButtonBackground: Color {
        switch voiceState {
        case .recording:     return .red
        case .transcribing:  return .orange
        default:             return .accentColor
        }
    }

    private var micButtonSymbol: String {
        switch voiceState {
        case .recording:    return "stop.fill"
        case .transcribing: return "waveform"
        default:            return mode == .voicePrompt ? "text.bubble" : "mic.fill"
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch voiceState {
        case .idle:
            Text(String(localized: mode == .voicePrompt
                        ? "voice.mic.speakInstruction"
                        : "voice.mic.tapToDictate"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .recording:
            Text(String(localized: "voice.mic.recording"))
                .font(.caption)
                .foregroundStyle(.red)
        case .transcribing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text(String(localized: "voice.mic.transcribing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(msg)
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Simple animated waveform using the recorder's level
    private var waveform: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 3, height: CGFloat(4 + Int(recorder.level * 12)) + CGFloat(i % 2 == 0 ? 2 : 0))
                    .animation(.easeInOut(duration: 0.1), value: recorder.level)
            }
        }
        .frame(height: 20)
    }

    // MARK: Actions

    private func toggleRecording() {
        switch voiceState {
        case .idle, .failed:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        guard let rec = audioRecorder else { return }
        do {
            try rec.start()
            voiceState = .recording
        } catch {
            voiceState = .failed(error.localizedDescription)
        }
    }

    private func stopAndTranscribe() {
        guard let wavURL = audioRecorder?.stop() else {
            voiceState = .idle
            return
        }
        voiceState = .transcribing

        transcriptionTask?.cancel()
        transcriptionTask = Task {
            do {
                let text = try await WhisperTranscriber.transcribe(wavURL: wavURL)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    voiceState = .idle
                    onTranscribed(text)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    voiceState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Prompt Row

private struct PromptRow: View {
    let prompt: DemoPrompt
    let shortcut: String
    let isSelected: Bool
    let onHover: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: prompt.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
                Text(prompt.title)
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
                Spacer()
                Text(shortcut)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.25) : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}
