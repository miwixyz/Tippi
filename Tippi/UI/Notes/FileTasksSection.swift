import SwiftUI

/// Abschnitt „Datei-Aufgaben“ unter den Notizen (2.38): offene Aufgaben aus Porters Liste.
/// Nur lesen; ein Klick öffnet die Datei in Porter (ohne Porter: im Finder zeigen).
/// Zeilen tragen keinen `.tag`, damit sie die Notizauswahl der Liste nicht berühren.
struct FileTasksSection: View {
    let state: PorterFileTasks.State

    var body: some View {
        Section(String(localized: "fileTasks.section")) {
            switch state {
            case .tasks(let items):
                ForEach(items) { row(for: $0) }
            case .empty:
                quietLine("fileTasks.empty")
            case .loading:
                quietLine("fileTasks.loading")
            case .unreadable:
                quietLine("fileTasks.unreadable")
            }
        }
    }

    private func row(for item: PorterFileTasks.Item) -> some View {
        Button {
            PorterFileTasks.open(item)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "circle")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.firstLine.isEmpty ? item.fileName : item.firstLine)
                        .font(FamilyTheme.font(.callout))
                        .lineLimit(1)
                    Text(item.firstLine.isEmpty ? item.folderName : item.fileName)
                        .font(FamilyTheme.font(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.key + (item.text.isEmpty ? "" : "\n\n" + item.text))
        .accessibilityLabel(Text(String(format: String(localized: "fileTasks.row.a11y"),
                                                 item.firstLine.isEmpty ? item.fileName : item.firstLine, item.fileName)))
    }

    private func quietLine(_ key: String) -> some View {
        Text(String(localized: String.LocalizationValue(key)))
            .font(FamilyTheme.font(.caption))
            .foregroundStyle(.secondary)
            // Sidebar-Zeilen kürzen sonst auf eine Zeile (gemessen im Bild 13.11.).
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
