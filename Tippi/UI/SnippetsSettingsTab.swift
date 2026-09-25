import SwiftUI

/// Settings → Text-Snippets. Two sources shown side by side: app-managed
/// snippets (full CRUD, no file editing needed — the "easier than Espanso"
/// path) and imported Espanso YAML files (read-only view; the file stays the
/// source of truth for anything using shell/date vars).
struct SnippetsTab: View {
    @EnvironmentObject var store: SnippetStore

    /// Two distinct jobs share this pane: words the transcription should spell
    /// a certain way, and shortcuts that expand into text. Related enough to
    /// live together, different enough that showing both at once was the main
    /// reason this pane had become a wall.
    private enum Section: String, CaseIterable, Identifiable {
        case words, snippets
        var id: String { rawValue }
        var title: String {
            switch self {
            case .words:    return String(localized: "settings.snippets.section.words")
            case .snippets: return String(localized: "settings.snippets.section.snippets")
            }
        }
    }

    @State private var section: Section = .words
    @State private var dictationCustomWords: [String] = DictationSettings.customWords
    @State private var newCustomWord: String = ""

    @State private var editingSnippet: AppSnippet?
    @State private var isAddingNew = false
    @State private var emojiInlineEnabled: Bool = EmojiSettings.isInlineEnabled
    @State private var emoticonEnabled: Bool = EmojiSettings.isEmoticonEnabled
    @State private var emojiSuggestionsEnabled: Bool = EmojiSettings.isSuggestionsEnabled

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 8)

            switch section {
            case .words:    customWordsPane
            case .snippets: snippetsPane
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorSheet(trigger: snippet.trigger, replacement: snippet.replacement,
                               vars: snippet.vars) { newTrigger, newReplacement, newVars in
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
        .sheet(item: $store.pendingShellApproval) { snippet in
            ShellSnippetApprovalSheet(
                snippet: snippet,
                onApprove: { store.approveShellSnippet(snippet) },
                onDecline: { store.declineShellSnippet(snippet) }
            )
        }
    }

    /// Words the user wants spelled a specific way. Lives here rather than in
    /// the dictation pane because this is where a user looks for "the app
    /// keeps writing my brand wrong" — it takes effect during the polish step,
    /// but that is an implementation detail, not where it belongs in the UI.
    @ViewBuilder
    private var customWordsPane: some View {
        Form {
            customWordsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var snippetsPane: some View {
        Form {
            SwiftUI.Section {
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
            SwiftUI.Section(String(localized: "settings.snippets.emoji.section")) {
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

            SwiftUI.Section(String(localized: "settings.snippets.appManaged")) {
                // The list being empty because the file could not be read looks
                // exactly like the list being empty because nothing was ever
                // created. Saying which one it is, is the whole point — the
                // silent version of this cost the file's contents.
                if let loadError = store.appSnippetsLoadError {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.snippets.loadError"))
                                .font(.caption)
                            Text(loadError)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            // Without this the only way out was relaunching,
                            // and the session in between silently dropped every
                            // new snippet: the list accepted them, nothing
                            // reached disk, all gone after the restart.
                            Button(String(localized: "settings.snippets.reloadFile")) {
                                store.reloadAppSnippets()
                            }
                            .controlSize(.small)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
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

            SwiftUI.Section(String(localized: "settings.snippets.reference")) {
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
                    // Files in this directory are no longer read live. Anyone
                    // upgrading from 2.9 finds their shortcuts dead while the
                    // file still sits here looking unchanged, with nothing to
                    // suggest that importing is now the step that makes it work.
                    Text(String(localized: "settings.snippets.importRequiredHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            SwiftUI.Section(String(localized: "settings.snippets.importedSnippets")) {
                if store.importedSnippets.isEmpty {
                    Text(String(localized: "settings.snippets.importedSnippetsEmpty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.importedSnippets) { snippet in
                        let shadowed = store.shadowedTriggers(of: snippet)
                        HStack {
                            Text(snippet.trigger).fontWeight(.medium)
                            Text("→").foregroundStyle(.secondary)
                            Text(snippet.replace)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            // Without the source file, two entries that share a
                            // trigger are indistinguishable in this list, and
                            // deleting the one that is actually inert becomes
                            // guesswork.
                            if let source = snippet.sourcePath {
                                Text(URL(fileURLWithPath: source).lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if !shadowed.isEmpty {
                                Label(String(localized: "settings.snippets.triggerShadowed"), systemImage: "arrow.uturn.forward")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .help(String(localized: "settings.snippets.triggerShadowedHelp"))
                            }
                            // Three states, not two. The badge used to read
                            // `shellApproval != nil` while activation asks
                            // `SnippetApprovalSigner.verify` — so a stored
                            // approval whose key is gone (Keychain reset,
                            // store restored from a backup onto another
                            // machine) showed a green "approved" over a
                            // snippet that silently never expands, with no way
                            // to fix it because only the orange badge was
                            // tappable. Now the badge asks the same question
                            // the expansion does.
                            if snippet.hasShellVars {
                                if snippet.shellApproval == nil {
                                    Label(String(localized: "settings.snippets.shellPending"), systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                        .onTapGesture { store.pendingShellApproval = snippet }
                                } else if store.isImportedSnippetActive(snippet) {
                                    Label(String(localized: "settings.snippets.shellApproved"), systemImage: "checkmark.shield.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                } else {
                                    Label(String(localized: "settings.snippets.shellUnverifiable"), systemImage: "exclamationmark.shield.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                        .onTapGesture { store.pendingShellApproval = snippet }
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
        }

    /// Terms the user wants spelled a specific way. Sits inside the polish
    /// section because that is where it takes effect: the list is appended to
    /// the system prompt as a spelling constraint at call time.
    ///
    /// Why this is needed at all, measured 2026-09-15: every polish model
    /// tested returned "CineWeb" for "CINEWEB", and the 4B one also flattened
    /// "CineSocial" to "Cinesocial". The word was heard correctly; the model
    /// simply normalised the capitalisation to what looks like an ordinary
    /// compound. No model in the list gets this right, because none of them can
    /// know a house spelling — it has to be supplied.
    @ViewBuilder
    private var customWordsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.voice.dictation.customWords.label"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "settings.voice.dictation.customWords.hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if dictationCustomWords.isEmpty {
                Text(String(localized: "settings.voice.dictation.customWords.empty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // Same row-with-trash shape the snippet list uses, rather than
                // a bespoke chip layout — one less custom layout to maintain
                // and it already matches what the rest of Settings looks like.
                ForEach(dictationCustomWords, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            dictationCustomWords.removeAll { $0 == word }
                            DictationSettings.customWords = dictationCustomWords
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField(String(localized: "settings.voice.dictation.customWords.placeholder"),
                          text: $newCustomWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCustomWord)
                Button(String(localized: "settings.voice.dictation.customWords.add"), action: addCustomWord)
                    .controlSize(.small)
                    .disabled(newCustomWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addCustomWord() {
        let word = newCustomWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        // Case-sensitive duplicate check on purpose: the whole point of an
        // entry is its exact capitalisation, so "CINEWEB" and "Cineweb" are
        // different entries and adding both is a user error worth showing
        // rather than silently merging.
        guard !dictationCustomWords.contains(word) else { newCustomWord = ""; return }
        dictationCustomWords.append(word)
        DictationSettings.customWords = dictationCustomWords
        newCustomWord = ""
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
                // Range comes from the builder, not a literal: it also defines
                // which commands are considered generatable at expansion time
                // (DynamicVariableBuilder.generatableCommands). A wider stepper
                // here than there would produce snippets the store then refuses.
                Stepper(value: $extraDays, in: DynamicVariableBuilder.extraDaysRange) {
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

/// Per-snippet consent for one imported shell command — the finer-grained
/// successor to `FileApprovalSheet` for anything that has actually been
/// imported into Tippi's own store (see docs/SECURE-DESIGN-espanso-import.md
/// § "per-snippet consent, integrity-protected"). Shown once per snippet, not
/// once per file: a harmless edit to an unrelated snippet in the same
/// original file no longer revokes this one's approval.
private struct ShellSnippetApprovalSheet: View {
    @EnvironmentObject var store: SnippetStore
    let snippet: ImportedSnippet
    let onApprove: () -> Void
    let onDecline: () -> Void

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

            if let error = store.approvalError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                // No `dismiss()` here on purpose. The store owns the binding
                // that presents this sheet: approving sets the *next* pending
                // item, declining clears it. `dismiss()` writes nil into that
                // same binding synchronously and wins over the assignment that
                // just happened — so with two shell snippets, or two files
                // awaiting approval, only the first was ever shown and the rest
                // stayed silently unapproved. Reproduced 2026-09-15.
                // Escape has to reach a button, and it must be this one: a
                // consent prompt that can only be answered by approving is not
                // consent. Without a cancel role, Escape did nothing at all.
                Button(String(localized: "settings.snippets.shellApproval.decline"), role: .cancel) {
                    onDecline()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "settings.snippets.shellApproval.approve")) {
                    onApprove()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
