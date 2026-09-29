import AppKit
import SwiftUI

/// Einstellungen → Sprache: Apps, in denen Tippi nach einem Diktat Enter drückt.
/// Leere Liste = Funktion aus (ab Werk). Die Liste bedient dieselben Bedienelemente
/// wie die Ausschlussliste der Autovervollständigung.
struct DictationAutoReturnSection: View {
    @State private var apps: [String] = DictationSettings.autoReturnBundleIDs

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.voice.dictation.autoReturn.title"))
                .font(FamilyTheme.font(.subheadline))
            Text(String(localized: "settings.voice.dictation.autoReturn.body"))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if apps.isEmpty {
                Text(String(localized: "settings.voice.dictation.autoReturn.empty"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
            }
            AppListEditor(
                bundleIDs: apps,
                onAdd: { save(apps + [$0]) },
                onRemove: { bundleID in save(apps.filter { $0 != bundleID }) }
            )
        }
    }

    private func save(_ list: [String]) {
        DictationSettings.autoReturnBundleIDs = list
        apps = DictationSettings.autoReturnBundleIDs
    }
}
