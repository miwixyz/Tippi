import SwiftUI

/// Settings → Text-Snippets. Two sources shown side by side: app-managed
/// snippets (full CRUD, no file editing needed — the "easier than Espanso"
/// path) and imported Espanso YAML files (read-only view; the file stays the
/// source of truth for anything using shell/date vars).
struct SnippetsTab: View {
    @EnvironmentObject var store: SnippetStore

    @State private var editingSnippet: AppSnippet?
    @State private var isAddingNew = false
    @State private var emojiInlineEnabled: Bool = EmojiSettings.isInlineEnabled
    @State private var emoticonEnabled: Bool = EmojiSettings.isEmoticonEnabled
    @State private var emojiSuggestionsEnabled: Bool = EmojiSettings.isSuggestionsEnabled

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.snippets.enabled"), isOn: $store.isEnabled)
                if store.isEnabled {
                    Text(String(localized: "settings.snippets.enabledHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                monitorStatusLine
                HStack {
                    Text(String(localized: "settings.snippets.prefix"))
                    Spacer()
                    TextField("", text: $store.defaultPrefix)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
            }

            // Lives here rather than in its own tab because it rides the exact
            // same keystroke watcher as snippet expansion — turning either on
            // starts it, turning both off stops it.
            Section(String(localized: "settings.snippets.emoji.section")) {
                Toggle(String(localized: "settings.snippets.emoji.enabled"), isOn: $emojiInlineEnabled)
                    .onChange(of: emojiInlineEnabled) { _, new in
                        EmojiSettings.isInlineEnabled = new
                        AppDelegate.shared?.applyKeystrokeMonitorState()
                    }
                Text(String(localized: "settings.snippets.emoji.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if emojiInlineEnabled {
                    Toggle(String(localized: "settings.snippets.emojiSuggestions.enabled"), isOn: $emojiSuggestionsEnabled)
                        .onChange(of: emojiSuggestionsEnabled) { _, new in
                            EmojiSettings.isSuggestionsEnabled = new
                        }
                    Text(String(localized: "settings.snippets.emojiSuggestions.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(String(localized: "settings.snippets.emoticon.enabled"), isOn: $emoticonEnabled)
                    .onChange(of: emoticonEnabled) { _, new in
                        EmojiSettings.isEmoticonEnabled = new
                        AppDelegate.shared?.applyKeystrokeMonitorState()
                    }
                Text(String(localized: "settings.snippets.emoticon.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(String(localized: "settings.snippets.appManaged")) {
                if store.appSnippets.isEmpty {
                    Text(String(localized: "settings.snippets.empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.appSnippets) { snippet in
                    HStack {
                        Text(snippet.trigger).fontWeight(.medium)
                        Text("→").foregroundStyle(.secondary)
                        Text(snippet.replacement)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            editingSnippet = snippet
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            store.removeSnippet(snippet)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    isAddingNew = true
                } label: {
                    Label(String(localized: "settings.snippets.new"), systemImage: "plus.circle")
                }
            }

            Section(String(localized: "settings.snippets.reference")) {
                if store.espansoFiles.isEmpty {
                    Text(String(localized: "settings.snippets.importedEmpty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.espansoFiles) { file in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(file.url.lastPathComponent).fontWeight(.medium)
                                Text("\(file.matchFile.matches.count)")
                                    + Text(" \(String(localized: "settings.snippets.matchCount"))")
                            }
                            .font(.caption)
                            Spacer()
                            if !file.isApproved {
                                Label(String(localized: "settings.snippets.shellPending"), systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .onTapGesture { store.pendingFileApproval = file }
                            } else {
                                Label(String(localized: "settings.snippets.shellApproved"), systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                            // Import replaces reference for this file — it
                            // works regardless of the file's current
                            // reference-approval state, and moves the file
                            // out of this list into "Importierte Kürzel"
                            // below (see SnippetStore.importFile).
                            Button(String(localized: "settings.snippets.import")) {
                                store.importFile(file)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                HStack {
                    Text(store.matchDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button(String(localized: "settings.snippets.rescan")) {
                        store.reloadEspansoFiles()
                    }
                }
            }

            Section(String(localized: "settings.snippets.importedSnippets")) {
                if store.importedSnippets.isEmpty {
                    Text(String(localized: "settings.snippets.importedSnippetsEmpty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.importedSnippets) { snippet in
                        HStack {
                            Text(snippet.trigger).fontWeight(.medium)
                            Text("→").foregroundStyle(.secondary)
                            Text(snippet.replace)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if snippet.hasShellVars {
                                if snippet.shellApproval == nil {
                                    Label(String(localized: "settings.snippets.shellPending"), systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                        .onTapGesture { store.pendingShellApproval = snippet }
                                } else {
                                    Label(String(localized: "settings.snippets.shellApproved"), systemImage: "checkmark.shield.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                            Button(role: .destructive) {
                                store.removeImportedSnippet(snippet)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorSheet(trigger: snippet.trigger, replacement: snippet.replacement, vars: snippet.vars) { newTrigger, newReplacement, newVars in
                var updated = snippet
                updated.trigger = newTrigger
                updated.replacement = newReplacement
                updated.vars = newVars
                store.updateSnippet(updated)
            }
        }
        .sheet(isPresented: $isAddingNew) {
            SnippetEditorSheet(trigger: store.defaultPrefix, replacement: "", vars: []) { trigger, replacement, vars in
                store.addSnippet(shortcut: trigger, replacement: replacement, vars: vars)
            }
        }
        .sheet(item: $store.pendingFileApproval) { file in
            FileApprovalSheet(
                file: file,
                onApprove: { store.approveFile(file) },
                onDecline: { store.declineFile(file) }
            )
        }
        .sheet(item: $store.pendingShellApproval) { snippet in
            ShellSnippetApprovalSheet(
                snippet: snippet,
                onApprove: { store.approveShellSnippet(snippet) },
                onDecline: { store.declineShellSnippet(snippet) }
            )
        }
    }

    /// Shows whether the keystroke watcher is actually running. Without this,
    /// "snippets don't expand" and "the monitor never started" look identical
    /// from the outside.
    ///
    /// Read through a computed property rather than an `@ObservedObject` with a
    /// custom `init()`: adding an initializer to this view interfered with how
    /// SwiftUI sets up its `@State`/`@EnvironmentObject` storage, and every
    /// toggle rendered as "off" while UserDefaults still said on (2026-09-14).
    /// The status is polled on redraw, which is enough for a settings pane.
    private var monitor: SnippetKeystrokeMonitor? { AppDelegate.shared?.snippetMonitor }

    /// Turns the two timestamps into one plain sentence. Deliberately not
    /// localized as marketing copy — this is a diagnostic line.
    private func diagnosticLine(received: Date?, processed: Date?) -> String {
        guard let received else {
            return String(localized: "settings.snippets.diag.noKeystrokes")
        }
        let age = Int(Date().timeIntervalSince(received))
        let recvText = String(format: String(localized: "settings.snippets.diag.received"), age)
        guard let processed else {
            return recvText + " · " + String(localized: "settings.snippets.diag.allFiltered")
        }
        let pAge = Int(Date().timeIntervalSince(processed))
        return recvText + " · " + String(format: String(localized: "settings.snippets.diag.processed"), pAge)
    }

    @ViewBuilder
    private var monitorStatusLine: some View {
        if let error = monitor?.lastError {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                if !AXIsProcessTrusted() {
                    Button(String(localized: "settings.permissions.grant")) {
                        let url = URL(string: "x-apple.systempreferences:"
                            + "com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            NSWorkspace.shared.runningApplications
                                .first { $0.bundleIdentifier == "com.apple.systempreferences" }?
                                .activate(options: [.activateAllWindows])
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        } else if let m = monitor, m.isActive, AXIsProcessTrusted() {
            VStack(alignment: .leading, spacing: 4) {
                Label(String(localized: "settings.snippets.monitorActive"),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                // Diagnostics: "active" alone has proven unreliable. These two
                // separate "no keystrokes arrive" from "keystrokes arrive but
                // get filtered out" (e.g. Tippi itself frontmost).
                Text(diagnosticLine(received: m.lastKeystrokeAt,
                                    processed: m.lastProcessedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else if monitor?.isActive == true && !AXIsProcessTrusted() {
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "error.accessibility.snippets"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(String(localized: "settings.permissions.grant")) {
                    let url = URL(string: "x-apple.systempreferences:"
                        + "com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NSWorkspace.shared.runningApplications
                            .first { $0.bundleIdentifier == "com.apple.systempreferences" }?
                            .activate(options: [.activateAllWindows])
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        } else {
            Label(String(localized: "settings.snippets.monitorInactive"),
                  systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SnippetEditorSheet: View {
    @State var trigger: String
    @State var replacement: String
    @State var vars: [SnippetVar]
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String, [SnippetVar]) -> Void

    @State private var showingVariablePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.snippets.editor.title")).font(.headline)
            TextField(String(localized: "settings.snippets.editor.trigger"), text: $trigger)
            TextField(String(localized: "settings.snippets.editor.replacement"), text: $replacement, axis: .vertical)
                .lineLimit(3...6)

            if !vars.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.snippets.editor.variablesInUse"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(vars, id: \.name) { variable in
                        Text("{{\(variable.name)}}")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                showingVariablePicker = true
            } label: {
                Label(String(localized: "settings.snippets.editor.insertVariable"), systemImage: "calendar.badge.plus")
            }

            HStack {
                Spacer()
                Button(String(localized: "settings.snippets.editor.cancel")) { dismiss() }
                Button(String(localized: "settings.snippets.editor.save")) {
                    onSave(trigger, replacement, vars)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || replacement.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .sheet(isPresented: $showingVariablePicker) {
            VariablePickerSheet { kind in
                // Unique per snippet-edit-session — collisions across
                // different snippets don't matter, `{{name}}` only needs to
                // be unique within one replacement template.
                let name = "var\(vars.count + 1)"
                vars.append(DynamicVariableBuilder.makeVar(name: name, kind: kind))
                replacement += "{{\(name)}}"
            }
        }
    }
}

/// The "idiot-proof" alternative to hand-typing a shell command: pick a kind
/// from a segmented control, fill in the couple of parameters that kind
/// needs (weekday, extra days, date format), done. Never shows or accepts
/// raw shell syntax.
private struct VariablePickerSheet: View {
    let onInsert: (DynamicVariableKind) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Mode: CaseIterable {
        case today, weekday, calendarWeek

        var label: String {
            switch self {
            case .today: return String(localized: "settings.snippets.variable.mode.today")
            case .weekday: return String(localized: "settings.snippets.variable.mode.weekday")
            case .calendarWeek: return String(localized: "settings.snippets.variable.mode.calendarWeek")
            }
        }
    }

    @State private var mode: Mode = .today
    @State private var format: DateFormatPreset = .dayMonthYear
    @State private var weekday: Weekday = .thursday
    @State private var extraDays: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.snippets.variable.title")).font(.headline)

            // Radio-group, not segmented: segmented control doesn't wrap —
            // "Wochentag dieser Woche" alone overflowed a 340pt-wide sheet
            // on both edges. A vertical list has no such width ceiling
            // regardless of label length or locale.
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch mode {
            case .today:
                Picker(String(localized: "settings.snippets.variable.format"), selection: $format) {
                    ForEach(DateFormatPreset.allCases, id: \.self) { f in Text(f.displayName).tag(f) }
                }
            case .weekday:
                Picker(String(localized: "settings.snippets.variable.weekday.label"), selection: $weekday) {
                    ForEach(Weekday.allCases, id: \.self) { w in Text(w.displayName).tag(w) }
                }
                Stepper(value: $extraDays, in: -30...30) {
                    Text(String(format: String(localized: "settings.snippets.variable.extraDays"), extraDays))
                }
                Picker(String(localized: "settings.snippets.variable.format"), selection: $format) {
                    ForEach(DateFormatPreset.allCases, id: \.self) { f in Text(f.displayName).tag(f) }
                }
            case .calendarWeek:
                Text(String(localized: "settings.snippets.variable.calendarWeekHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(String(localized: "settings.snippets.editor.cancel")) { dismiss() }
                Button(String(localized: "settings.snippets.variable.insert")) {
                    let kind: DynamicVariableKind
                    switch mode {
                    case .today: kind = .today(format: format)
                    case .weekday: kind = .weekday(weekday, extraDays: extraDays, format: format)
                    case .calendarWeek: kind = .calendarWeek
                    }
                    onInsert(kind)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// Shown for every newly-appeared or changed match file before its triggers
/// go live — not only ones with shell commands. Anything with write access
/// to the watched directory could otherwise silently redefine an existing
/// trigger with zero visible consent; the wording just adapts to what's
/// actually being approved (explicit shell commands vs. plain trigger text).
private struct FileApprovalSheet: View {
    let file: LoadedEspansoFile
    let onApprove: () -> Void
    let onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var shellCommands: [String] {
        file.matchFile.matches
            .flatMap(\.vars)
            .filter { $0.type == "shell" }
            .compactMap(\.params.cmd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: file.containsShellVars ? "settings.snippets.shellApproval.title" : "settings.snippets.fileApproval.title"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            if file.containsShellVars {
                Text(String(format: String(localized: "settings.snippets.shellApproval.body"), file.url.lastPathComponent))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(shellCommands, id: \.self) { cmd in
                            Text(cmd).font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            } else {
                Text(String(format: String(localized: "settings.snippets.fileApproval.body"), file.url.lastPathComponent))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(file.matchFile.matches.flatMap(\.triggers), id: \.self) { trigger in
                            Text(trigger).font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }

            HStack {
                Spacer()
                Button(String(localized: "settings.snippets.shellApproval.decline")) {
                    onDecline()
                    dismiss()
                }
                Button(String(localized: "settings.snippets.shellApproval.approve")) {
                    onApprove()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Per-snippet consent for one imported shell command — the finer-grained
/// successor to `FileApprovalSheet` for anything that has actually been
/// imported into Tippi's own store (see docs/SECURE-DESIGN-espanso-import.md
/// § "per-snippet consent, integrity-protected"). Shown once per snippet, not
/// once per file: a harmless edit to an unrelated snippet in the same
/// original file no longer revokes this one's approval.
private struct ShellSnippetApprovalSheet: View {
    let snippet: ImportedSnippet
    let onApprove: () -> Void
    let onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var shellCommands: [String] {
        snippet.vars.filter { $0.type == "shell" }.compactMap(\.params.cmd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "settings.snippets.shellSnippetApproval.title"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(String(format: String(localized: "settings.snippets.shellSnippetApproval.body"), snippet.trigger))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(shellCommands, id: \.self) { cmd in
                    Text(cmd).font(.system(.caption, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)

            HStack {
                Spacer()
                Button(String(localized: "settings.snippets.shellApproval.decline")) {
                    onDecline()
                    dismiss()
                }
                Button(String(localized: "settings.snippets.shellApproval.approve")) {
                    onApprove()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
