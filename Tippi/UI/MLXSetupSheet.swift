import SwiftUI

/// Modal sheet that walks a non-technical user through installing the MLX
/// toolchain (`uv` + `mlx-lm`). Shown from Settings → Providers → MLX when
/// `mlx_lm.server` is not yet on disk.
struct MLXSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var phase: MLXInstaller.Phase = .checking
    @State private var logLines: [String] = []
    @State private var running = false
    @State private var finished = false
    @State private var streamTask: Task<Void, Never>?

    private let manualCommands = "uv tool install mlx-lm"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "mlx.install.title"))
                        .font(.title2).bold()
                    Text(String(localized: "mlx.install.subtitle"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Phases
            VStack(alignment: .leading, spacing: 8) {
                phaseRow(
                    icon: "shippingbox",
                    label: String(localized: "mlx.install.phase.uv"),
                    state: phaseState(.installingUV)
                )
                phaseRow(
                    icon: "brain",
                    label: String(localized: "mlx.install.phase.mlxlm"),
                    state: phaseState(.installingMLXLM)
                )
            }

            // Live log
            GroupBox {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: 160, maxHeight: 220)
                    .onChange(of: logLines.count) { _, newCount in
                        guard newCount > 0 else { return }
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }

            // Status / error message
            if case .failed(let msg) = phase {
                VStack(alignment: .leading, spacing: 6) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Text(String(localized: "mlx.install.fallbackHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(manualCommands)
                            .font(.system(.caption, design: .monospaced))
                            .padding(6)
                            .background(.quaternary.opacity(0.4))
                            .cornerRadius(4)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(manualCommands, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "mlx.install.copyCommand"))
                    }
                }
            } else if case .done = phase {
                Label(String(localized: "mlx.install.success"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                    .symbolEffect(.bounce)
            }

            // Actions
            HStack {
                Spacer()
                if !running && !finished {
                    Button(String(localized: "mlx.install.cancel")) { dismiss() }
                    Button(String(localized: "mlx.install.start")) { startInstall() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else if running {
                    ProgressView().controlSize(.small)
                    Text(phase.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "mlx.install.cancel")) {
                        streamTask?.cancel()
                        streamTask = nil
                        running = false
                        dismiss()
                    }
                } else if finished {
                    Button(String(localized: "mlx.install.close")) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            // First run: surface initial detection state to the user before they
            // click Install. The actual install starts when they press Start.
            if MLXInstaller.isUVInstalled {
                logLines.append("• uv detected at \(MLXInstaller.resolvedUVPath() ?? "?")")
            } else {
                logLines.append("• uv not found — will be installed first")
            }
        }
    }

    // MARK: - Phase row

    private enum RowState { case pending, active, done, failed, skipped }

    private func phaseRow(icon: String, label: String, state: RowState) -> some View {
        HStack(spacing: 10) {
            switch state {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            case .active:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: icon).frame(width: 20)
            Text(label).font(.callout)
            Spacer()
        }
    }

    private func phaseState(_ target: MLXInstaller.Phase) -> RowState {
        switch (phase, target) {
        case (.installingUV, .installingUV):       return .active
        case (.installingMLXLM, .installingMLXLM): return .active
        case (.installingMLXLM, .installingUV):    return .done
        case (.done, _):                            return .done
        case (.failed, .installingUV):              return MLXInstaller.isUVInstalled ? .done : .failed
        case (.failed, .installingMLXLM):           return .failed
        default:                                    return .pending
        }
    }

    // MARK: - Run

    private func startInstall() {
        guard !running else { return }
        running = true
        finished = false
        logLines.append("")
        logLines.append("→ Starting installation…")

        streamTask = Task { @MainActor in
            for await event in MLXInstaller.install() {
                switch event {
                case .log(let line):
                    if !line.isEmpty { logLines.append(line) }
                case .phaseChanged(let p):
                    phase = p
                case .finished:
                    running = false
                    finished = true
                }
            }
        }
    }
}
