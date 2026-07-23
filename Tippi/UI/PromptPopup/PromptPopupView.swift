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
    let localActions: [LocalTextAction]
    let localActionsReady: Bool
    let onSelect: (DemoPrompt) -> Void
    let onLocalAction: (LocalTextAction) async -> String?
    let onDismiss: () -> Void
    var onDirectInsert: (() -> Void)? = nil
    var audioRecorder: AudioRecorder? = nil
    var onVoiceTranscribed: ((String) -> Void)? = nil
    var voiceMode: VoiceMode = .dictate

    // -1 means the "Direkt einfügen" row is highlighted (only when onDirectInsert != nil)
    @State private var selectedIndex: Int
    @State private var localActionMessage: String?
    // True while the inline instruction TextField holds focus — suspends the
    // container's keyboard navigation so typed characters and Return go to the
    // field instead of selecting a prompt from the list.
    @State private var instructionFieldActive = false
    // Alfred-style type-to-search filter. Empty = no filter (all prompts shown,
    // digit shortcuts 1–9 remain active). Non-empty = live filter, digits and
    // letters go into the query buffer instead of firing shortcuts.
    @State private var searchQuery: String = ""
    @FocusState private var focused: Bool

    init(
        prompts: [DemoPrompt],
        localActions: [LocalTextAction] = [],
        localActionsReady: Bool = true,
        onSelect: @escaping (DemoPrompt) -> Void,
        onLocalAction: @escaping (LocalTextAction) async -> String? = { _ in nil },
        onDismiss: @escaping () -> Void,
        onDirectInsert: (() -> Void)? = nil,
        audioRecorder: AudioRecorder? = nil,
        onVoiceTranscribed: ((String) -> Void)? = nil,
        voiceMode: VoiceMode = .dictate
    ) {
        self.prompts = prompts
        self.localActions = localActions
        self.localActionsReady = localActionsReady
        self.onSelect = onSelect
        self.onLocalAction = onLocalAction
        self.onDismiss = onDismiss
        self.onDirectInsert = onDirectInsert
        self.audioRecorder = audioRecorder
        self.onVoiceTranscribed = onVoiceTranscribed
        self.voiceMode = voiceMode
        // Always start at first AI prompt (index 0).
        // "Direkt einfügen" row (index -1) is visible but requires explicit click or ↑ arrow.
        _selectedIndex = State(initialValue: 0)
    }

    /// Prompts filtered by the current search query (title-only, case-insensitive
    /// substring). Empty query returns the full list unchanged.
    private var filteredPrompts: [DemoPrompt] {
        guard !searchQuery.isEmpty else { return prompts }
        return prompts.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !localActions.isEmpty {
                        localActionsSection
                        Divider()
                            .padding(.horizontal, 10)
                    }
                    list
                }
            }
            .frame(maxHeight: 420)
            if audioRecorder != nil || !WhisperConfig.isConfigured {
                Divider()
                VoiceSection(
                    audioRecorder: audioRecorder,
                    mode: voiceMode,
                    onTranscribed: onVoiceTranscribed ?? { _ in },
                    onFieldFocusChange: { instructionFieldActive = $0 },
                    onInstructionChange: { newText in
                        searchQuery = newText
                        selectedIndex = 0
                    }
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
        .onAppear {
            // In voice-prompt mode the instruction field auto-focuses itself so
            // the user can type immediately — don't steal focus back to the
            // container (that would disable typing). Dictate mode keeps the
            // container focused for digit/arrow prompt navigation.
            if !(voiceMode == .voicePrompt && audioRecorder != nil) {
                focused = true
            }
        }
        .onKeyPress(.escape) {
            // Two-stage escape: first clears an active search query, second closes.
            if !searchQuery.isEmpty {
                searchQuery = ""
                selectedIndex = 0
                return .handled
            }
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !instructionFieldActive else { return .ignored }
            let minIndex = onDirectInsert != nil && searchQuery.isEmpty ? -1 : 0
            selectedIndex = max(minIndex, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !instructionFieldActive else { return .ignored }
            guard !filteredPrompts.isEmpty else { return .handled }
            selectedIndex = min(filteredPrompts.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !instructionFieldActive else { return .ignored }
            if selectedIndex == -1 && searchQuery.isEmpty {
                onDirectInsert?()
            } else if filteredPrompts.indices.contains(selectedIndex) {
                onSelect(filteredPrompts[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.delete) {
            // Backspace shrinks the search query one char at a time.
            guard !instructionFieldActive, !searchQuery.isEmpty else { return .ignored }
            searchQuery.removeLast()
            selectedIndex = 0
            return .handled
        }
        .onKeyPress { keyPress in
            guard !instructionFieldActive else { return .ignored }
            // Only pure key input (no ⌘/⌃/⌥) participates in shortcuts or search.
            guard keyPress.modifiers.isDisjoint(with: [.command, .control, .option]) else {
                return .ignored
            }
            guard let first = keyPress.characters.first else { return .ignored }

            // Digit shortcut 1–9 only fires when no query is active; otherwise
            // digits go into the query buffer alongside letters.
            if searchQuery.isEmpty, let digit = Int(String(first)),
               digit >= 1 && digit <= filteredPrompts.count {
                onSelect(filteredPrompts[digit - 1])
                return .handled
            }

            // Type-to-search: append any alphanumeric or space character.
            if first.isLetter || first.isNumber || first == " " || first == "-" {
                searchQuery.append(first)
                selectedIndex = 0
                return .handled
            }
            return .ignored
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            // Show the search glass only when the query originates from the
            // container (direct type-to-search, dictate mode). When the
            // instruction field is active the query is visible in the text
            // field below, so keep the header neutral to avoid duplication.
            Image(systemName: (!searchQuery.isEmpty && !instructionFieldActive)
                  ? "magnifyingglass" : "pencil.and.outline")
                .foregroundStyle(.tint)
            if !searchQuery.isEmpty && !instructionFieldActive {
                Text(searchQuery)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("Tippi")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            // Match-count is always shown when a filter is active, regardless
            // of source — visual confirmation that filtering is running.
            if !searchQuery.isEmpty {
                Text("\(filteredPrompts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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
            if filteredPrompts.isEmpty && !searchQuery.isEmpty {
                Text(String(localized: "prompt.search.noMatch"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            ForEach(Array(filteredPrompts.enumerated()), id: \.element.id) { index, prompt in
                PromptRow(
                    // Only 1–9 are reachable via the digit shortcut, and only
                    // when no search query is active (digits go into the query
                    // buffer while filtering).
                    prompt: prompt,
                    shortcut: (searchQuery.isEmpty && index < 9) ? "\(index + 1)" : "",
                    isSelected: index == selectedIndex,
                    onHover: { selectedIndex = index },
                    onTap: { onSelect(prompt) }
                )
            }
        }
        .padding(.vertical, 6)
    }

    private var localActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "local.actions.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if !localActionsReady {
                Text(String(localized: "local.actions.needsSelection"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(localActions) { action in
                    LocalActionButton(action: action) {
                        Task { @MainActor in
                            let message = await onLocalAction(action)
                            localActionMessage = message
                            if message == nil {
                                onDismiss()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)

            if let localActionMessage {
                Text(localActionMessage)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 6)
    }
}

private struct LocalActionButton: View {
    let action: LocalTextAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: action.symbol)
                    .frame(width: 14)
                    .foregroundStyle(Color.accentColor)
                Text(action.title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
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
    var onFieldFocusChange: (Bool) -> Void = { _ in }
    /// Called on every keystroke in the instruction field. Parent uses this to
    /// mirror the text into `searchQuery` for ambient prompt filtering.
    var onInstructionChange: (String) -> Void = { _ in }

    private enum State { case idle, recording, transcribing, failed(String) }
    @SwiftUI.State private var voiceState: State = .idle
    @SwiftUI.State private var transcriptionTask: Task<Void, Never>?
    @SwiftUI.State private var typedInstruction: String = ""
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var recorder: AudioRecorder

    init(
        audioRecorder: AudioRecorder?,
        mode: VoiceMode,
        onTranscribed: @escaping (String) -> Void,
        onFieldFocusChange: @escaping (Bool) -> Void = { _ in },
        onInstructionChange: @escaping (String) -> Void = { _ in }
    ) {
        self.audioRecorder = audioRecorder
        self.mode          = mode
        self.onTranscribed = onTranscribed
        self.onFieldFocusChange = onFieldFocusChange
        self.onInstructionChange = onInstructionChange
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

    private var isIdleOrFailed: Bool {
        if case .idle = voiceState { return true }
        if case .failed = voiceState { return true }
        return false
    }

    @ViewBuilder
    private var voiceControls: some View {
        HStack(spacing: 10) {
            micButton
            if mode == .voicePrompt && isIdleOrFailed {
                instructionField
            } else {
                statusText
                Spacer()
                if case .recording = voiceState {
                    waveform
                }
            }
        }
    }

    /// Inline text field for typing an instruction (voicePrompt mode only).
    private var instructionField: some View {
        HStack(spacing: 4) {
            TextField(
                String(localized: "voice.instruction.placeholder"),
                text: $typedInstruction
            )
            .textFieldStyle(.plain)
            .font(.caption)
            .focused($fieldFocused)
            .onSubmit { submitTyped() }
            .onChange(of: fieldFocused) { _, focused in
                onFieldFocusChange(focused)
            }
            // Ambient prompt filtering: mirror the typed instruction into the
            // parent's search query on every keystroke. The list re-filters live
            // while the user drafts their instruction — no extra shortcut,
            // Return still fires `submitTyped()` (free instruction), and ↓+Return
            // picks from the pre-filtered list.
            .onChange(of: typedInstruction) { _, new in
                onInstructionChange(new)
            }
            // Auto-focus so the user can type the instruction without a click.
            .onAppear {
                if mode == .voicePrompt {
                    DispatchQueue.main.async { fieldFocused = true }
                }
            }
            // ↓ hands keyboard navigation back to the prompt list.
            .onKeyPress(.downArrow) {
                fieldFocused = false
                return .handled
            }
            // When the field leaves the tree (e.g. recording starts), the
            // focus onChange may not fire — release the container lock here
            // so keyboard navigation of the prompt list stays alive.
            .onDisappear { onFieldFocusChange(false) }

            if !typedInstruction.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: submitTyped) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func submitTyped() {
        let instruction = typedInstruction.trimmingCharacters(in: .whitespaces)
        guard !instruction.isEmpty else { return }
        typedInstruction = ""
        onTranscribed(instruction)
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
            // No recorder → tapping would silently do nothing; disable it.
            if audioRecorder == nil { return true }
            if case .transcribing = voiceState { return true }
            return false
        }())
        .opacity(audioRecorder == nil ? 0.4 : 1)
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
            // Warm the engine while the user is speaking, so a cold first
            // transcription doesn't stall on loading the model.
            SpeechTranscriber.prewarm()
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
                let text = try await SpeechTranscriber.transcribe(wavURL: wavURL)
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
                if !shortcut.isEmpty {
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
