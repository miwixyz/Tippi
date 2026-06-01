import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → History tab.
///
/// The tab is the user's full control surface over the encrypted local history:
/// toggle recording, browse / inspect / delete individual entries, export
/// everything as JSON or CSV, or wipe the whole store.
struct HistoryTab: View {
    @State private var isEnabled: Bool = HistoryStore.shared.isEnabled
    @State private var entries: [HistoryEntry] = []
    @State private var totalCount: Int = 0
    @State private var loadError: String?
    @State private var selectedEntry: HistoryEntry?
    @State private var confirmDeleteAll: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    Text(String(localized: "settings.history.toggle.label"))
                }
                .onChange(of: isEnabled) { _, newValue in
                    HistoryStore.shared.isEnabled = newValue
                    if newValue { refresh() }
                }
                Text(isEnabled
                     ? String(localized: "settings.history.toggle.on.hint")
                     : String(localized: "settings.history.toggle.off.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                entriesSection
                actionsSection
            }
        }
        .formStyle(.grouped)
        .onAppear { if isEnabled { refresh() } }
        .sheet(item: $selectedEntry) { entry in
            HistoryDetailView(entry: entry) { selectedEntry = nil }
        }
        .alert(
            String(localized: "settings.history.deleteAll.confirm.title"),
            isPresented: $confirmDeleteAll
        ) {
            Button(
                String(localized: "settings.history.deleteAll.confirm.cancel"),
                role: .cancel
            ) { }
            Button(
                String(localized: "settings.history.deleteAll.confirm.ok"),
                role: .destructive
            ) { deleteAll() }
        } message: {
            Text(String(localized: "settings.history.deleteAll.confirm.body"))
        }
    }

    // MARK: - Sections

    private var entriesSection: some View {
        Section(String(localized: "settings.history.section.entries")) {
            if entries.isEmpty {
                Text(String(localized: "settings.history.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HistoryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEntry = entry }
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(entry)
                            } label: {
                                Label(
                                    String(localized: "settings.history.delete"),
                                    systemImage: "trash"
                                )
                            }
                        }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            HStack {
                Button(String(localized: "settings.history.export.json")) {
                    export(format: .json)
                }
                Button(String(localized: "settings.history.export.csv")) {
                    export(format: .csv)
                }
                Spacer()
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label(
                        String(localized: "settings.history.deleteAll"),
                        systemImage: "trash"
                    )
                }
                .disabled(totalCount == 0)
            }
            HStack {
                Text(String(
                    format: String(localized: "settings.history.count.entries"),
                    totalCount
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let err = loadError {
                    Spacer()
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        do {
            entries = try HistoryStore.shared.fetch(limit: 200)
            totalCount = try HistoryStore.shared.count()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ entry: HistoryEntry) {
        do {
            try HistoryStore.shared.delete(id: entry.id)
            refresh()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteAll() {
        do {
            try HistoryStore.shared.deleteAll()
            refresh()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private enum ExportFormat { case json, csv }

    private func export(format: ExportFormat) {
        let panel = NSSavePanel()
        let stamp = Self.fileTimestamp()
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "tippi-history-\(stamp).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "tippi-history-\(stamp).csv"
        }
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch format {
            case .json: data = try HistoryStore.shared.exportJSON()
            case .csv:  data = try HistoryStore.shared.exportCSV()
            }
            try data.write(to: url, options: [.atomic])
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static func fileTimestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        return df.string(from: Date())
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.promptTitle)
                    .font(.callout)
                    .bold()
                Text(entry.input)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.timestamp, format: .relative(presentation: .numeric))
                    .font(.caption)
                Text("\(entry.appName) · \(entry.provider)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail sheet

private struct HistoryDetailView: View {
    let entry: HistoryEntry
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.promptTitle).font(.headline)
                    Text(detailSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            HSplitView {
                paneInput
                paneOutput
            }
        }
        .frame(width: 760, height: 520)
    }

    private var detailSubtitle: String {
        var parts: [String] = [entry.appName, "\(entry.provider) / \(entry.model ?? "—")"]
        parts.append("\(entry.latencyMs) ms")
        parts.append(entry.timestamp.formatted(date: .abbreviated, time: .standard))
        return parts.joined(separator: " · ")
    }

    private var paneInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.history.detail.input"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(entry.input)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(minWidth: 200)
    }

    private var paneOutput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.history.detail.output"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(entry.output)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(minWidth: 200)
    }
}
