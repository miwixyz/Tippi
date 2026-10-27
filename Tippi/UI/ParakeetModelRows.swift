import SwiftUI

/// Settings → Voice → Speech engine, shown when Parakeet is selected: which
/// Parakeet build (v3 or Ultra, 2026-10-27) and whether it is on disk / loaded.
/// Out of `VoiceTab` (SwiftLint `type_body_length`), the status row unchanged.
struct ParakeetModelRows: View {
    @State private var parakeetModel: ParakeetModel = .current
    @ObservedObject private var parakeetStatus = ParakeetStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            parakeetModelRow
            parakeetStatusRow
        }
    }

    /// v3 or Ultra (2026-10-27). v3 stays the default until Ultra is measured
    /// on real German dictations; each build downloads on its own.
    private var parakeetModelRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.voice.parakeetModel.title"))
                Text(String(localized: "settings.voice.parakeetModel.hint"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker("", selection: $parakeetModel) {
                ForEach(ParakeetModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .onChange(of: parakeetModel) { _, new in
                ParakeetModel.current = new
                parakeetStatus.refreshFromDisk(force: true)
            }
        }
    }

    @ViewBuilder
    private var parakeetStatusRow: some View {
        HStack(spacing: 8) {
            switch parakeetStatus.phase {
            case .notDownloaded:
                Label(String(localized: "settings.voice.engine.status.notDownloaded"),
                      systemImage: "exclamationmark.circle")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.orange)
                Spacer()
                Button(String(localized: "settings.voice.engine.download")) {
                    Task { await ParakeetTranscriber.shared.prewarm() }
                }
                .controlSize(.small)
            case .downloading(let fraction):
                Text(String(localized: "settings.voice.engine.status.downloading"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                ProgressView(value: fraction)
                    .frame(maxWidth: 160)
                Text("\(Int(fraction * 100)) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "settings.voice.engine.status.loading"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
            case .ready:
                Label(String(format: String(localized: "settings.voice.engine.status.ready"),
                             parakeetModel.displayName),
                      systemImage: "checkmark.circle.fill")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.green)
                Spacer()
            case .failed(let message):
                Label(message, systemImage: "xmark.circle")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button(String(localized: "settings.voice.engine.download")) {
                    Task { await ParakeetTranscriber.shared.prewarm() }
                }
                .controlSize(.small)
            }
        }
    }
}
