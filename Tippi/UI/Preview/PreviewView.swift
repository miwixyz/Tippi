import SwiftUI

struct PreviewView: View {
    let prompt: DemoPrompt
    let originalText: String
    let sourceAppName: String?

    @State private var state: ViewState
    @State private var task: Task<Void, Never>?

    let onReplace: (String) -> Void
    let onAppend: (String) -> Void
    let onCopy: (String) -> Void
    let onCancel: () -> Void

    enum ViewState {
        case loading
        case ready(text: String, providerInfo: String?)
        case failed(message: String)
    }

    init(
        prompt: DemoPrompt,
        originalText: String,
        sourceAppName: String?,
        onReplace: @escaping (String) -> Void,
        onAppend: @escaping (String) -> Void,
        onCopy: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.originalText = originalText
        self.sourceAppName = sourceAppName
        self.onReplace = onReplace
        self.onAppend = onAppend
        self.onCopy = onCopy
        self.onCancel = onCancel
        _state = State(initialValue: .loading)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 640, height: 480)
        .onAppear { runCompletion() }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: prompt.symbol).foregroundStyle(.tint)
            Text(prompt.title)
                .font(.headline)
            if let sourceAppName {
                Text("· \(sourceAppName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .ready(_, let info?) = state {
                providerBadge(info)
            } else if case .ready = state {
                fallbackBadge
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func providerBadge(_ info: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cloud").font(.caption2)
            Text(info)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .foregroundStyle(.tint)
    }

    private var fallbackBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "cloud.slash").font(.caption2)
            Text(String(localized: "preview.fallback.badge"))
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.18)))
        .foregroundStyle(.orange)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 14) {
                ProgressView().scaleEffect(1.4)
                Text(String(localized: "preview.loading"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let suggestion, _):
            HStack(spacing: 0) {
                column(
                    label: String(localized: "preview.original"),
                    text: originalText,
                    tint: .secondary
                )
                Divider()
                column(
                    label: String(localized: "preview.suggestion"),
                    text: suggestion,
                    tint: .accentColor,
                    background: .tippiMist.opacity(0.4)
                )
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(String(localized: "preview.errorLabel"))
                    .font(.headline)
                Text(message)
                    .font(.callout.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func column(label: String, text: String, tint: Color, background: Color = .clear) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(tint)
            ScrollView {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(String(localized: "preview.cancel"), action: cancel)
                .keyboardShortcut(.escape)

            Spacer()

            if case .ready(let suggestion, _) = state {
                Button(String(localized: "preview.copy")) { onCopy(suggestion) }
                Button(String(localized: "preview.append")) { onAppend(suggestion) }
                Button(String(localized: "preview.regenerate"), action: runCompletion)
                Button(String(localized: "preview.replace")) { onReplace(suggestion) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            } else if case .failed = state {
                Button(String(localized: "preview.retry"), action: runCompletion)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func runCompletion() {
        task?.cancel()
        state = .loading
        task = Task { @MainActor in
            do {
                let result = try await LLMRouter.shared.complete(
                    systemPrompt: prompt.systemPrompt,
                    userText: originalText
                )
                guard !Task.isCancelled else { return }
                state = .ready(text: result.text, providerInfo: result.providerDisplay)
            } catch LLMError.noProviderConfigured, LLMError.noAPIKey {
                guard !Task.isCancelled else { return }
                let fallback = prompt.transform(originalText)
                state = .ready(text: fallback, providerInfo: nil)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    private func cancel() {
        task?.cancel()
        onCancel()
    }
}
