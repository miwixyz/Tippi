import AppKit
import SwiftUI

// MARK: - Prompts tab

/// Settings → Prompts: one list of every prompt — built-in and custom mixed, in
/// the order the popup shows them (`DemoPrompt.all`). Drag to reorder; the first
/// nine get the digit keys 1–9. Every prompt is editable; an edited built-in can
/// be reset to its original, a custom one deleted (both after a confirmation).
struct PromptsTab: View {
    @ObservedObject private var store = CustomPromptStore.shared
    @ObservedObject private var edits = BuiltInPromptEditStore.shared
    @ObservedObject private var order = PromptOrderStore.shared
    @State private var editTarget: EditTarget?
    @State private var pendingDelete: CustomPrompt?
    @State private var pendingReset: DemoPrompt?
    @State private var pendingImportData: Data?
    @State private var importMessage: String?

    /// What the editor sheet is open for. A new prompt gets its UUID up front,
    /// so its provider choice can be stored under its final id on save.
    private enum EditTarget: Identifiable {
        case builtIn(String)
        case custom(CustomPrompt)
        case new(UUID)

        var id: String {
            switch self {
            case .builtIn(let promptID): return promptID
            case .custom(let prompt): return prompt.demoID
            case .new(let uuid): return CustomPrompt.demoID(uuid)
            }
        }
    }

    var body: some View {
        let prompts = DemoPrompt.all
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(String(localized: "settings.prompts.listHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                    row(prompt, index: index)
                }
                .onMove { order.move(prompts.map(\.id), fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if let msg = importMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("✓") ? Color.secondary : Color.orange)
                    .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // ── Import merge / replace alert ──────────────────────────────────────
        .alert(
            String(localized: "prompts.import.alert.title"),
            isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            )
        ) {
            Button(String(localized: "prompts.import.merge")) { doImport(merge: true) }
            Button(String(localized: "prompts.import.replace"), role: .destructive) { doImport(merge: false) }
            Button(String(localized: "prompts.import.cancel"), role: .cancel) { pendingImportData = nil }
        } message: {
            Text(String(localized: "prompts.import.alert.message"))
        }
        .alert(
            String(format: String(localized: "settings.prompts.deleteConfirm.title"), pendingDelete?.title ?? ""),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button(String(localized: "settings.prompts.delete"), role: .destructive) {
                if let prompt = pendingDelete { store.delete(id: prompt.id) }
                pendingDelete = nil
            }
            Button(String(localized: "demo.sheet.cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(String(localized: "settings.prompts.deleteConfirm.message"))
        }
        .alert(
            String(format: String(localized: "settings.prompts.resetConfirm.title"), pendingReset?.title ?? ""),
            isPresented: Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } })
        ) {
            Button(String(localized: "settings.prompts.reset"), role: .destructive) {
                if let prompt = pendingReset { edits.reset(id: prompt.id) }
                pendingReset = nil
            }
            Button(String(localized: "demo.sheet.cancel"), role: .cancel) { pendingReset = nil }
        } message: {
            Text(String(localized: "settings.prompts.resetConfirm.message"))
        }
        .sheet(item: $editTarget) { target in
            editor(for: target)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "settings.tab.prompts"))
                .font(.headline)
            Spacer()
            Button(action: importPrompts) {
                Label(String(localized: "prompts.import.button"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            if !store.prompts.isEmpty {
                Button(action: exportAll) {
                    Label(String(localized: "prompts.export.all"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
            Button(action: { editTarget = .new(UUID()) }) {
                Label(String(localized: "settings.prompts.new"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Row

    private func row(_ prompt: DemoPrompt, index: Int) -> some View {
        let custom = store.prompts.first { $0.demoID == prompt.id }
        let isEdited = custom == nil && edits.isEdited(prompt.id)
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(String(localized: "settings.prompts.dragHint"))
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Image(systemName: prompt.symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(prompt.title)
                .lineLimit(1)
            badge(custom == nil
                  ? String(localized: "settings.prompts.builtIn")
                  : String(localized: "settings.prompts.badge.custom"))
            if isEdited { badge(String(localized: "settings.prompts.badge.edited")) }
            Spacer()
            if let custom {
                Button(action: { exportSingle(custom) }) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "prompts.export.one"))
            }
            Button(action: { editTarget = custom.map(EditTarget.custom) ?? .builtIn(prompt.id) }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "settings.prompts.edit"))
            if let custom {
                Button(action: { pendingDelete = custom }) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "settings.prompts.delete"))
            } else if isEdited {
                Button(action: { pendingReset = prompt }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "settings.prompts.reset"))
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for target: EditTarget) -> some View {
        switch target {
        case .builtIn(let promptID):
            if let original = DemoPrompt.builtIn.first(where: { $0.id == promptID }) {
                PromptEditor(
                    heading: String(localized: "settings.prompts.editor.titleEdit"),
                    promptID: promptID,
                    draft: PromptDraft(original.applying(edits.edits[promptID])),
                    isBuiltIn: true
                ) { draft in
                    if let draft {
                        edits.set(BuiltInPromptEdit(
                            original: original,
                            title: draft.title,
                            symbol: draft.symbol.isEmpty ? original.symbol : draft.symbol,
                            systemPrompt: draft.systemPrompt,
                            pipeline: draft.pipeline
                        ), for: promptID)
                    }
                    editTarget = nil
                }
            }
        case .custom(let prompt):
            PromptEditor(
                heading: String(localized: "settings.prompts.editor.titleEdit"),
                promptID: prompt.demoID,
                draft: PromptDraft(prompt.asDemoPrompt()),
                isBuiltIn: false
            ) { draft in
                if let draft { store.update(draft.customPrompt(id: prompt.id)) }
                editTarget = nil
            }
        case .new(let uuid):
            PromptEditor(
                heading: String(localized: "settings.prompts.editor.titleNew"),
                promptID: CustomPrompt.demoID(uuid),
                draft: PromptDraft(),
                isBuiltIn: false
            ) { draft in
                if let draft { store.add(draft.customPrompt(id: uuid)) }
                editTarget = nil
            }
        }
    }

    // MARK: - Export

    private func exportAll() {
        exportPrompts(store.prompts, suggestedName: "Tippi-Prompts.tippipack")
    }

    private func exportSingle(_ prompt: CustomPrompt) {
        let safeName = prompt.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        exportPrompts([prompt], suggestedName: "Tippi-\(safeName).tippipack")
    }

    private func exportPrompts(_ prompts: [CustomPrompt], suggestedName: String) {
        guard let data = try? store.packageData(for: prompts) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.title = String(localized: "prompts.export.panel.title")
        panel.message = String(localized: "prompts.export.panel.message")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                showImportMessage(String(localized: "prompts.export.failed"))
            }
        }
    }

    // MARK: - Import

    private func importPrompts() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "prompts.import.panel.title")
        panel.message = String(localized: "prompts.import.panel.message")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else {
                showImportMessage(String(localized: "prompts.import.failed"))
                return
            }
            self.pendingImportData = data
        }
    }

    private func doImport(merge: Bool) {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            let count = try store.importPackage(from: data, merge: merge)
            showImportMessage(String(format: String(localized: "prompts.import.success"), count))
        } catch {
            showImportMessage(String(localized: "prompts.import.failed"))
        }
    }

    private func showImportMessage(_ msg: String) {
        importMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { importMessage = nil }
        }
    }
}

// MARK: - Editor

/// The editable fields of any prompt, built-in or custom.
private struct PromptDraft {
    var title = ""
    var symbol = "wand.and.stars"
    var systemPrompt = ""
    var pipeline: [String]?

    init() {}

    init(_ prompt: DemoPrompt) {
        title = prompt.title
        symbol = prompt.symbol
        systemPrompt = prompt.instructions
        pipeline = prompt.pipeline
    }

    init(title: String, symbol: String, systemPrompt: String, pipeline: [String]?) {
        self.title = title
        self.symbol = symbol
        self.systemPrompt = systemPrompt
        self.pipeline = pipeline
    }

    func customPrompt(id: UUID) -> CustomPrompt {
        CustomPrompt(id: id, title: title, symbol: symbol, systemPrompt: systemPrompt, pipeline: pipeline)
    }
}

private struct PromptEditor: View {
    let heading: String
    /// `DemoPrompt.id` of the prompt being edited — excluded from its own chain
    /// steps, and the key its provider choice is stored under.
    let promptID: String
    /// Built-ins keep their type: a single-step prompt stays single, the chain a chain.
    let isBuiltIn: Bool
    let onSave: (PromptDraft?) -> Void

    private enum Mode: Hashable { case single, chain }

    @State private var title: String
    @State private var symbol: String
    @State private var systemPrompt: String
    @State private var mode: Mode
    @State private var pipeline: [String]
    @State private var providerOverride: String
    @State private var modelOverride: String

    init(heading: String, promptID: String, draft: PromptDraft, isBuiltIn: Bool,
         onSave: @escaping (PromptDraft?) -> Void) {
        self.heading = heading
        self.promptID = promptID
        self.isBuiltIn = isBuiltIn
        self.onSave = onSave
        _title = State(initialValue: draft.title)
        _symbol = State(initialValue: draft.symbol)
        _systemPrompt = State(initialValue: draft.systemPrompt)
        _mode = State(initialValue: (draft.pipeline?.isEmpty ?? true) ? .single : .chain)
        _pipeline = State(initialValue: draft.pipeline ?? [])
        _providerOverride = State(initialValue: PromptProviderOverride.providerID(for: promptID))
        _modelOverride = State(initialValue: PromptProviderOverride.modelOverride(for: promptID))
    }

    /// Prompts that can be used as chain steps: every non-chain prompt except
    /// the one being edited (a chain can't reference itself, and chain-in-chain
    /// is out of scope).
    private var availableSteps: [DemoPrompt] {
        DemoPrompt.all.filter { !$0.isChain && $0.id != promptID }
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch mode {
        case .single: return !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .chain: return pipeline.count >= 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
            if isBuiltIn {
                Text(String(localized: "settings.prompts.editor.builtInHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(String(localized: "settings.prompts.editor.titlePlaceholder"),
                      text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField(String(localized: "settings.prompts.editor.symbolPlaceholder"),
                          text: $symbol)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: symbol.isEmpty ? "wand.and.stars" : symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
            }

            if !isBuiltIn {
                Picker(String(localized: "settings.prompts.editor.mode"), selection: $mode) {
                    Text(String(localized: "settings.prompts.editor.mode.single")).tag(Mode.single)
                    Text(String(localized: "settings.prompts.editor.mode.chain")).tag(Mode.chain)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if mode == .single {
                singleEditor
            } else {
                chainEditor
            }

            Spacer(minLength: 0)

            PromptProviderPicker(provider: $providerOverride, model: $modelOverride)

            HStack {
                Button(String(localized: "demo.sheet.cancel")) { onSave(nil) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(String(localized: "settings.providers.save"), action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
    }

    private func save() {
        PromptProviderOverride.setProviderID(providerOverride, for: promptID)
        PromptProviderOverride.setModelOverride(providerOverride.isEmpty ? "" : modelOverride, for: promptID)
        onSave(PromptDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: mode == .single
                ? systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                : "",
            pipeline: mode == .chain ? pipeline : nil
        ))
    }

    // MARK: - Single-step editor

    private var singleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.prompts.editor.symbolHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(localized: "settings.prompts.editor.systemLabel"))
                .font(.caption)
            TextEditor(text: $systemPrompt)
                .font(.body)
                .frame(minHeight: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

            Text(String(localized: "settings.prompts.editor.systemHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(localized: "settings.prompts.editor.variablesHint"))
                .font(.caption)
                .foregroundStyle(.tint)
        }
    }

    // MARK: - Chain editor

    private var chainEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.prompts.editor.chainHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if pipeline.isEmpty {
                Text(String(localized: "settings.prompts.editor.chainEmpty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(pipeline.enumerated()), id: \.offset) { index, stepID in
                        chainRow(index: index, stepID: stepID)
                    }
                }
                .frame(minHeight: 120, alignment: .top)
            }

            Menu {
                ForEach(availableSteps) { step in
                    Button {
                        pipeline.append(step.id)
                    } label: {
                        Label(step.title, systemImage: step.symbol)
                    }
                }
            } label: {
                Label(String(localized: "settings.prompts.editor.chainAddStep"), systemImage: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func chainRow(index: Int, stepID: String) -> some View {
        let step = DemoPrompt.resolve(id: stepID)
        return HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: step?.symbol ?? "questionmark.circle")
                .foregroundStyle(step == nil ? Color.red : Color.accentColor)
                .frame(width: 20)
            Text(step?.title ?? String(localized: "settings.prompts.editor.chainMissing"))
                .foregroundStyle(step == nil ? Color.red : Color.primary)
            Spacer()
            Button {
                guard index > 0 else { return }
                pipeline.swapAt(index, index - 1)
            } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
            Button {
                guard index < pipeline.count - 1 else { return }
                pipeline.swapAt(index, index + 1)
            } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(index == pipeline.count - 1)
            Button {
                pipeline.remove(at: index)
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
    }
}

/// Provider/model choice for one prompt, independent of the global default.
/// Exists because a default that's great for short dictation polish (small
/// local model, fast) can be hopeless on a long prompt like "Improve" run
/// against a multi-paragraph business email — reproduced 2026-09-01: MLX
/// Qwen3.5 2B returned such an email completely unchanged. Rather than force a
/// bigger/cloud model globally, this pins one prompt to a different provider.
/// Moved from the former per-row pickers into the editor (25 pickers stacked
/// up made the list unreadable).
private struct PromptProviderPicker: View {
    @Binding var provider: String
    @Binding var model: String

    private static let useActive = "__active__"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "settings.prompts.editor.provider"))
                    .font(.caption)
                Picker("", selection: providerBinding) {
                    Text(String(localized: "settings.voice.dictation.postProcess.providerActive"))
                        .tag(Self.useActive)
                    Divider()
                    ForEach(LLMRouter.allProviders, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            if !provider.isEmpty {
                let modelPresets = ProviderModelPresets.presets(for: provider)
                if !modelPresets.isEmpty {
                    HStack {
                        Text(String(localized: "settings.providers.model"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model) {
                            ForEach(modelPresets) { preset in
                                Text(preset.label).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            Text(String(localized: "settings.prompts.editor.providerHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { provider.isEmpty ? Self.useActive : provider },
            set: { new in
                let value = (new == Self.useActive) ? "" : new
                provider = value
                if !value.isEmpty, let fastest = ProviderModelPresets.defaultPolishModel(for: value) {
                    model = fastest
                } else {
                    model = ""
                }
            }
        )
    }
}
