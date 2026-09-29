import SwiftUI

/// Trigger + replacement editor for both snippet lists in Settings → Snippets.
/// Moved out of SnippetsSettingsTab.swift (together with the variable picker)
/// when imported snippets became editable and that file crossed the
/// file_length ratchet.
struct SnippetEditorSheet: View {
    /// One field per trigger: own snippets have exactly one, an imported
    /// Espanso match may carry several.
    @State var triggers: [String]
    @State var replacement: String
    @State var vars: [SnippetVar]
    /// Off for imported snippets: their vars came from the file, and the
    /// editor changes triggers and text only.
    var allowsVariables = true
    var notice: String?
    @Environment(\.dismiss) private var dismiss
    let onSave: ([String], String, [SnippetVar]) -> Void

    @State private var showingVariablePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.snippets.editor.title")).font(FamilyTheme.font(.headline))
            ForEach(triggers.indices, id: \.self) { index in
                TextField(String(localized: "settings.snippets.editor.trigger"), text: $triggers[index])
            }
            TextField(String(localized: "settings.snippets.editor.replacement"), text: $replacement, axis: .vertical)
                .lineLimit(3...6)

            if !vars.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.snippets.editor.variablesInUse"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                    ForEach(vars, id: \.name) { variable in
                        Text("{{\(variable.name)}}")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if allowsVariables {
                Button {
                    showingVariablePicker = true
                } label: {
                    Label(String(localized: "settings.snippets.editor.insertVariable"), systemImage: "calendar.badge.plus")
                }
            }

            if let notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(String(localized: "settings.snippets.editor.cancel")) { dismiss() }
                Button(String(localized: "settings.snippets.editor.save")) {
                    onSave(triggers, replacement, vars)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(triggers.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty } || replacement.isEmpty)
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
            Text(String(localized: "settings.snippets.variable.title")).font(FamilyTheme.font(.headline))

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
                    .font(FamilyTheme.font(.caption))
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
