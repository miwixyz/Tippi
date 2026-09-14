import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var permissions: PermissionsManager
    @State private var step: Int = 0
    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(currentStep: step, totalSteps: totalSteps)
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 12)

            Divider()

            Group {
                switch step {
                case 0: WelcomeIntroStep()
                case 1: AccessibilityStep()
                case 2: InputMonitoringStep()
                case 3: APIKeyStep()
                case 4: TryItStep()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)

            Divider()

            HStack {
                Button(String(localized: "setup.back")) {
                    step -= 1
                }
                .disabled(step == 0)

                Spacer()

                if step < totalSteps - 1 {
                    Button(String(localized: "setup.next")) {
                        step += 1
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "setup.finish")) {
                        UserDefaults.standard.set(true, forKey: "setupCompleted")
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep
                          ? Color.accentColor
                          : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Step Content

private struct WelcomeIntroStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text(String(localized: "welcome.title"))
                .font(.largeTitle)
                .bold()
            Text(String(localized: "welcome.subtitle"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccessibilityStep: View {
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: permissions.accessibilityGranted
                  ? "checkmark.circle.fill"
                  : "lock.circle")
                .font(.system(size: 56))
                .foregroundStyle(permissions.accessibilityGranted ? Color.green : Color.orange)

            Text(String(localized: "setup.accessibility.title"))
                .font(.title)
                .bold()

            Text(String(localized: "setup.accessibility.body"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            StatusPill(granted: permissions.accessibilityGranted)

            HStack(spacing: 12) {
                Button(String(localized: "setup.openSettings")) {
                    permissions.requestAccessibilityPrompt()
                    permissions.openAccessibilitySettings()
                }
                Button(String(localized: "setup.checkAgain")) {
                    permissions.refresh()
                }
            }
        }
    }
}

private struct InputMonitoringStep: View {
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: permissions.inputMonitoringGranted
                  ? "checkmark.circle.fill"
                  : "keyboard.badge.eye")
                .font(.system(size: 48))
                .foregroundStyle(permissions.inputMonitoringGranted ? Color.green : Color.orange)

            Text(String(localized: "setup.inputMonitoring.title"))
                .font(.title)
                .bold()

            Text(String(localized: "setup.inputMonitoring.body"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            StatusPill(granted: permissions.inputMonitoringGranted)

            if !permissions.inputMonitoringGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "setup.inputMonitoring.manualHeader"))
                        .font(.callout.bold())
                    Text(String(localized: "setup.inputMonitoring.manualStep1"))
                        .font(.caption)
                    Text(String(localized: "setup.inputMonitoring.manualStep2"))
                        .font(.caption)
                    Text(String(localized: "setup.inputMonitoring.manualStep3"))
                        .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }

            HStack(spacing: 12) {
                Button(String(localized: "setup.openSettings")) {
                    permissions.requestInputMonitoringPrompt()
                    permissions.openInputMonitoringSettings()
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "setup.checkAgain")) {
                    permissions.refresh()
                }
            }
        }
    }
}

private struct APIKeyStep: View {
    @State private var apiKey: String = ""
    @State private var feedback: String?
    @State private var feedbackIsError: Bool = false
    @State private var hasExistingKey: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text(String(localized: "setup.apiKey.title"))
                .font(.title)
                .bold()

            Text(String(localized: "setup.apiKey.body"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasExistingKey {
                Label(String(localized: "setup.apiKey.alreadySaved"),
                      systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            SecureField(String(localized: "setup.apiKey.placeholder"), text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            Button(String(localized: "setup.apiKey.save")) {
                do {
                    try KeychainStore.setAPIKey(apiKey, for: "openai")
                    feedback = String(localized: "setup.apiKey.saved")
                    feedbackIsError = false
                    hasExistingKey = true
                } catch {
                    feedback = error.localizedDescription
                    feedbackIsError = true
                }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let feedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(feedbackIsError ? Color.red : Color.green)
            }

            Text(String(localized: "setup.apiKey.skip"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            hasExistingKey = KeychainStore.hasAPIKey(for: "openai")
        }
    }
}

private struct TryItStep: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @State private var clickCount = 0
    @State private var showingDemoSheet = false

    private var demoText: String {
        String(localized: "setup.tryIt.demo.text")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text(String(localized: "setup.tryIt.title"))
                    .font(.title)
                    .bold()

                Text(String(localized: "setup.tryIt.demo.heading"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(demoText)
                    .font(.body)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                    )

                Button {
                    clickCount += 1
                    showingDemoSheet = true
                } label: {
                    Label(String(localized: "setup.tryIt.testButton"),
                          systemImage: "wand.and.stars")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)

                if clickCount > 0 {
                    Text(String(format: String(localized: "setup.tryIt.clickCount"), clickCount))
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Text(String(localized: "setup.tryIt.testHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider().padding(.vertical, 4)

                Text(String(localized: "setup.tryIt.hotkey.heading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "setup.tryIt.hotkey"))
                    .font(.callout.monospaced())
                    .bold()

                HotkeyStatusBadge()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingDemoSheet) {
            DemoSheet(originalText: demoText, onClose: { showingDemoSheet = false })
        }
    }
}

private struct DemoSheet: View {
    let originalText: String
    let onClose: () -> Void
    @State private var state: SheetState = .picking
    @State private var task: Task<Void, Never>?

    enum ResultSource: Equatable {
        case llm(info: String)
        case localFallback
    }

    enum SheetState {
        case picking
        case loading(DemoPrompt)
        case result(prompt: DemoPrompt, text: String, source: ResultSource)
        case failed(prompt: DemoPrompt, message: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(.tint)
                Text("Tippi — Demo")
                    .font(.headline)
                Spacer()
                Button(String(localized: "demo.sheet.close"), action: closeSheet)
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 480)
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .picking:
            DemoPromptList(original: originalText, onPick: pick)
        case .loading(let prompt):
            DemoLoadingView(prompt: prompt, onCancel: cancel)
        case .result(let prompt, let text, let source):
            DemoResultView(
                prompt: prompt,
                original: originalText,
                result: text,
                source: source,
                onBack: { state = .picking },
                onClose: closeSheet
            )
        case .failed(let prompt, let message):
            DemoFailedView(
                prompt: prompt,
                message: message,
                onRetry: { pick(prompt) },
                onBack: { state = .picking },
                onClose: closeSheet
            )
        }
    }

    private func pick(_ prompt: DemoPrompt) {
        task?.cancel()
        state = .loading(prompt)
        task = Task { @MainActor in
            do {
                let result = try await LLMRouter.shared.complete(
                    systemPrompt: prompt.systemPrompt,
                    userText: originalText
                )
                guard !Task.isCancelled else { return }
                state = .result(prompt: prompt, text: result.text, source: .llm(info: result.providerDisplay))
            } catch LLMError.noProviderConfigured, LLMError.noAPIKey {
                guard !Task.isCancelled else { return }
                let fallback = prompt.transform(originalText)
                state = .result(prompt: prompt, text: fallback, source: .localFallback)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(prompt: prompt, message: error.localizedDescription)
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        state = .picking
    }

    private func closeSheet() {
        task?.cancel()
        task = nil
        onClose()
    }
}

private struct DemoLoadingView: View {
    let prompt: DemoPrompt
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.4)
            HStack(spacing: 8) {
                Image(systemName: prompt.symbol).foregroundStyle(.tint)
                Text(prompt.title).font(.headline)
            }
            Text(String(localized: "demo.sheet.loading"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(String(localized: "demo.sheet.cancel"), role: .cancel, action: onCancel)
                .keyboardShortcut(.escape)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DemoFailedView: View {
    let prompt: DemoPrompt
    let message: String
    let onRetry: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(prompt.title).font(.headline)
            }

            Text(String(localized: "demo.sheet.errorLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.12))
                )
                .textSelection(.enabled)

            Spacer()

            HStack {
                Button(String(localized: "demo.sheet.tryAnother"), action: onBack)
                Spacer()
                Button(String(localized: "demo.sheet.retry"), action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                Button(String(localized: "demo.sheet.close"), action: onClose)
            }
        }
        .padding()
    }
}

private struct DemoPromptList: View {
    let original: String
    let onPick: (DemoPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "demo.sheet.originalLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(original)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )

            Text(String(localized: "demo.sheet.pickAction"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(spacing: 4) {
                ForEach(DemoPrompt.all) { prompt in
                    Button {
                        onPick(prompt)
                    } label: {
                        HStack {
                            Image(systemName: prompt.symbol)
                                .frame(width: 22)
                                .foregroundStyle(.tint)
                            Text(prompt.title)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.06))
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DemoResultView: View {
    let prompt: DemoPrompt
    let original: String
    let result: String
    let source: DemoSheet.ResultSource
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: prompt.symbol)
                    .foregroundStyle(.tint)
                Text(prompt.title)
                    .font(.headline)
                Spacer()
                sourceBadge
            }

            Text(String(localized: "demo.sheet.originalLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(original)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )

            Text(String(localized: "demo.sheet.resultLabel"))
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.top, 6)
            Text(result)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.12))
                )
                .textSelection(.enabled)

            Spacer()

            HStack {
                Button(String(localized: "demo.sheet.tryAnother"), action: onBack)
                Spacer()
                Button(String(localized: "demo.sheet.close"), action: onClose)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch source {
        case .llm(let info):
            HStack(spacing: 4) {
                Image(systemName: "cloud").font(.caption2)
                Text(info)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.15))
            )
            .foregroundStyle(.tint)
        case .localFallback:
            HStack(spacing: 4) {
                Image(systemName: "cloud.slash").font(.caption2)
                Text(String(localized: "demo.sheet.localFallbackBadge"))
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.orange.opacity(0.18))
            )
            .foregroundStyle(.orange)
        }
    }
}

private struct HotkeyStatusBadge: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        Group {
            if hotkeyManager.lastError != nil {
                Label(String(localized: "setup.tryIt.inactive"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if hotkeyManager.isActive {
                if let last = hotkeyManager.lastTriggerAt {
                    Label(
                        String(format: String(localized: "setup.tryIt.lastTrigger"),
                               last.formatted(date: .omitted, time: .standard)),
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label(String(localized: "setup.tryIt.listening"),
                          systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(String(localized: "setup.tryIt.inactive"),
                      systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

// MARK: - Helpers

private struct StatusPill: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(granted
                 ? String(localized: "setup.granted")
                 : String(localized: "setup.notGranted"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
