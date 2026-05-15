import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gear") }
            HotkeysTab()
                .tabItem { Label(String(localized: "settings.tab.hotkeys"), systemImage: "command") }
            ProvidersTab()
                .tabItem { Label(String(localized: "settings.tab.providers"), systemImage: "key") }
            PromptsTab()
                .tabItem { Label(String(localized: "settings.tab.prompts"), systemImage: "text.bubble") }
            VoiceTab()
                .tabItem { Label(String(localized: "settings.tab.voice"), systemImage: "mic") }
            HelpTab()
                .tabItem { Label(String(localized: "settings.tab.help"), systemImage: "questionmark.circle") }
            AboutTab()
                .tabItem { Label(String(localized: "settings.tab.about"), systemImage: "info.circle") }
        }
        .frame(width: 640, height: 580)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var autostart: Bool = false
    @State private var autostartStatus: String = ""

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.general.autostart"), isOn: $autostart)
                    .onChange(of: autostart) { _, new in
                        toggleAutostart(new)
                    }
                if !autostartStatus.isEmpty {
                    Text(autostartStatus)
                        .font(.caption)
                        .foregroundStyle(autostartStatus.hasPrefix("⚠️") ? Color.orange : Color.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { refresh() }
    }

    private func refresh() {
        if #available(macOS 13.0, *) {
            autostart = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleAutostart(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            autostartStatus = "⚠️ Needs macOS 13+"
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                autostartStatus = String(localized: "settings.general.autostart.enabled")
            } else {
                try SMAppService.mainApp.unregister()
                autostartStatus = String(localized: "settings.general.autostart.disabled")
            }
        } catch {
            autostartStatus = "⚠️ \(error.localizedDescription)"
            autostart = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @EnvironmentObject var keyMonitor: GlobalKeyMonitor

    @State private var combo: KeyCombo = KeyComboStore.load()
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "settings.hotkeys.header"))
                            .font(.headline)
                        Text(String(localized: "settings.hotkeys.intro"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HotkeyRecorderField(combo: $combo)
                            .onChange(of: combo) { _, new in
                                KeyComboStore.save(new)
                                keyMonitor.update(combo: new)
                                savedFlash = true
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    savedFlash = false
                                }
                            }

                        Text(String(localized: "settings.hotkeys.restartHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button(String(localized: "settings.hotkeys.reset")) {
                                combo = .default
                            }
                            .buttonStyle(.bordered)
                            Button(String(localized: "settings.hotkeys.testTrigger")) {
                                (NSApp.delegate as? AppDelegate)?.triggerManually()
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                            if savedFlash {
                                Text(String(localized: "settings.providers.savedFlash"))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        Divider()
                        statusLine
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.hotkeys.macOSHeader"))
                            .font(.headline)
                        Text(String(localized: "settings.hotkeys.macOSBody"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(String(localized: "settings.hotkeys.macOSOpen")) {
                            let url = URL(string:
                                "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
                            )!
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "settings.hotkeys.tipHeader"))
                            .font(.headline)
                        Text(String(localized: "settings.hotkeys.tip1"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "settings.hotkeys.tip2"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let err = keyMonitor.lastError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if keyMonitor.isActive {
            Label(
                String(format: String(localized: "settings.hotkeys.active"),
                       keyMonitor.combo.displayString),
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        } else {
            Label(String(localized: "settings.hotkeys.inactive"),
                  systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Providers

private struct ProvidersTab: View {
    @State private var selectedProvider: String = LLMRouter.preferredProviderID
    @State private var refreshTick: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                defaultPickerCard
                ForEach(LLMRouter.allProviders.indices, id: \.self) { index in
                    let provider = LLMRouter.allProviders[index]
                    ProviderRow(provider: provider, refreshTick: refreshTick) {
                        refreshTick += 1
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var defaultPickerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "settings.providers.default"))
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $selectedProvider) {
                        ForEach(LLMRouter.allProviders.indices, id: \.self) { index in
                            let p = LLMRouter.allProviders[index]
                            Text(p.displayName).tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .onChange(of: selectedProvider) { _, new in
                        LLMRouter.setPreferredProvider(new)
                    }
                }
                Text(String(localized: "settings.providers.default.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }
}

private struct ProviderRow: View {
    let provider: LLMProvider
    let refreshTick: Int
    let onSaved: () -> Void

    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    @State private var hasKey: Bool = false
    @State private var savedFlash: Bool = false

    // MLX-only
    @ObservedObject private var mlxManager = MLXServerManager.shared
    @State private var mlxPort: String = "\(MLXServerManager.port)"
    @State private var mlxPreset: String = "custom"

    private var isMLX: Bool { provider.id == "mlx" }

    // MARK: - MLX model presets

    struct MLXPreset: Identifiable {
        let id: String
        let label: String
        let repoID: String
    }

    static let mlxPresets: [MLXPreset] = [
        // 8 GB
        MLXPreset(id: "qwen35-08b",    label: "Qwen3.5 0.8B — 8 GB",       repoID: "mlx-community/Qwen3.5-0.8B-MLX-8bit"),
        MLXPreset(id: "qwen35-2b",     label: "Qwen3.5 2B — 8 GB",         repoID: "mlx-community/Qwen3.5-2B-MLX-8bit"),
        // 16 GB
        MLXPreset(id: "qwen35-9b",     label: "Qwen3.5 9B — 16 GB ⭐",     repoID: "mlx-community/Qwen3.5-9B-MLX-8bit"),
        MLXPreset(id: "llama31-8b-4b", label: "Llama 3.1 8B 4bit — 16 GB", repoID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"),
        // 32 GB
        MLXPreset(id: "llama31-8b-3b", label: "Llama 3.1 8B 3bit — 32 GB", repoID: "mlx-community/Meta-Llama-3.1-8B-Instruct-3bit"),
        MLXPreset(id: "qwen25-14b",    label: "Qwen2.5 14B — 32 GB ⭐",    repoID: "mlx-community/Qwen2.5-14B-Instruct-4bit"),
        MLXPreset(id: "deepseek-r1",   label: "DeepSeek-R1 7B — 32 GB",    repoID: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit"),
    ]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(provider.displayName)
                        .font(.headline)
                    Spacer()
                    statusBadge
                }

                Text(hint(for: provider.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if provider.requiresAPIKey {
                    SecureField(String(localized: "settings.providers.apiKey"),
                                text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                if isMLX {
                    mlxModelPicker
                } else {
                    HStack {
                        Text(String(localized: "settings.providers.model"))
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)
                        TextField(provider.defaultModel, text: $modelName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // ── MLX extras ──────────────────────────────────────────────
                if isMLX {
                    HStack {
                        Text(String(localized: "settings.providers.mlx.port"))
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)
                        TextField("8080", text: $mlxPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(mlxStatusColor)
                            .frame(width: 8, height: 8)
                        Text(mlxManager.state.displayLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if mlxManager.state.isRunning {
                            Button(String(localized: "settings.providers.mlx.stop")) {
                                mlxManager.stop()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button(String(localized: "settings.providers.mlx.start")) {
                                Task { try? await mlxManager.start() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(mlxManager.state == .starting)
                        }
                    }
                }
                // ────────────────────────────────────────────────────────────

                HStack {
                    if savedFlash {
                        Text(String(localized: "settings.providers.savedFlash"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button(String(localized: "settings.providers.save"), action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(saveDisabled)
                }
            }
            .padding(6)
        }
        .onAppear(perform: load)
        .onChange(of: refreshTick) { _, _ in load() }
    }

    private var mlxModelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "settings.providers.model"))
                    .font(.caption)
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $mlxPreset) {
                    ForEach(Self.mlxPresets) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                    Divider()
                    Text(String(localized: "settings.providers.mlx.custom")).tag("custom")
                }
                .labelsHidden()
                .onChange(of: mlxPreset) { _, newPreset in
                    if let preset = Self.mlxPresets.first(where: { $0.id == newPreset }) {
                        modelName = preset.repoID
                    }
                }
            }
            if mlxPreset == "custom" {
                TextField("mlx-community/…", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 60)
                    .font(.caption)
            } else {
                Text(modelName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 60)
            }
        }
    }

    private var mlxStatusColor: Color {
        switch mlxManager.state {
        case .running:  return .green
        case .starting: return .orange
        case .failed:   return .red
        case .stopped:  return .gray
        }
    }

    private var statusBadge: some View {
        Group {
            if !provider.requiresAPIKey {
                Label(String(localized: "settings.providers.localBadge"),
                      systemImage: "house.fill")
                    .foregroundStyle(.secondary)
            } else if hasKey {
                Label(String(localized: "settings.providers.keySaved"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(String(localized: "settings.providers.noKey"),
                      systemImage: "key.slash")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private var saveDisabled: Bool {
        provider.requiresAPIKey
            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() {
        if provider.requiresAPIKey {
            apiKey = (try? KeychainStore.getAPIKey(for: provider.id)) ?? ""
            hasKey = KeychainStore.hasAPIKey(for: provider.id)
        } else {
            apiKey = ""
            hasKey = true
        }
        modelName = UserDefaults.standard.string(forKey: "defaultModel.\(provider.id)") ?? ""
        if isMLX {
            mlxPort = "\(MLXServerManager.port)"
            if let match = Self.mlxPresets.first(where: { $0.repoID == modelName || $0.repoID == (UserDefaults.standard.string(forKey: "defaultModel.mlx") ?? MLXServerManager.model) }) {
                mlxPreset = match.id
                modelName = match.repoID
            } else {
                mlxPreset = "custom"
                if modelName.isEmpty { modelName = MLXServerManager.model }
            }
        }
    }

    private func save() {
        if provider.requiresAPIKey {
            try? KeychainStore.setAPIKey(apiKey, for: provider.id)
        }
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty {
            UserDefaults.standard.removeObject(forKey: "defaultModel.\(provider.id)")
        } else {
            UserDefaults.standard.set(trimmedModel, forKey: "defaultModel.\(provider.id)")
        }
        if isMLX, let p = Int(mlxPort.trimmingCharacters(in: .whitespaces)), p > 0 {
            let modelChanged = !trimmedModel.isEmpty && trimmedModel != MLXServerManager.model
            let portChanged  = p != MLXServerManager.port
            if !trimmedModel.isEmpty { MLXServerManager.model = trimmedModel }
            MLXServerManager.port = p
            if (modelChanged || portChanged) && mlxManager.state.isRunning {
                mlxManager.stop()
            }
        }
        load()
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
        onSaved()
    }

    private func hint(for id: String) -> String {
        switch id {
        case "openai":    return String(localized: "settings.providers.hint.openai")
        case "anthropic": return String(localized: "settings.providers.hint.anthropic")
        case "gemini":    return String(localized: "settings.providers.hint.gemini")
        case "mistral":   return String(localized: "settings.providers.hint.mistral")
        case "ollama":    return String(localized: "settings.providers.hint.ollama")
        case "mlx":       return String(localized: "settings.providers.hint.mlx")
        default:          return ""
        }
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @StateObject private var store = CustomPromptStore.shared
    @State private var editing: CustomPrompt?
    @State private var creatingNew: Bool = false
    @State private var pendingImportData: Data?
    @State private var importMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ── Built-in prompts ──────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.prompts.builtIn"))
                            .font(.headline)
                        ForEach(DemoPrompt.builtIn) { p in
                            HStack {
                                Image(systemName: p.symbol)
                                    .foregroundStyle(.tint)
                                    .frame(width: 22)
                                Text(p.title)
                                Spacer()
                                Text(String(localized: "settings.prompts.readOnly"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(6)
                }

                // ── Custom prompts ────────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(String(localized: "settings.prompts.custom"))
                                .font(.headline)
                            Spacer()
                            Button(action: importPrompts) {
                                Label(String(localized: "prompts.import.button"),
                                      systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderless)
                            if !store.prompts.isEmpty {
                                Button(action: exportAll) {
                                    Label(String(localized: "prompts.export.all"),
                                          systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                            Button(action: { creatingNew = true }) {
                                Label(String(localized: "settings.prompts.new"),
                                      systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                        if store.prompts.isEmpty {
                            Text(String(localized: "settings.prompts.empty"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            List {
                                ForEach(store.prompts) { p in
                                    HStack {
                                        Image(systemName: p.symbol)
                                            .foregroundStyle(.tint)
                                            .frame(width: 22)
                                        Text(p.title)
                                        Spacer()
                                        Button(action: { exportSingle(p) }) {
                                            Image(systemName: "square.and.arrow.up")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)
                                        .help(String(localized: "prompts.export.one"))
                                        Button(action: { editing = p }) {
                                            Image(systemName: "pencil")
                                        }
                                        .buttonStyle(.borderless)
                                        Button(action: { store.delete(id: p.id) }) {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                            }
                            .listStyle(.plain)
                            .frame(minHeight: CGFloat(store.prompts.count) * 36)
                        }
                    }
                    .padding(6)
                }

                // ── Import status message ─────────────────────────────────────
                if let msg = importMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("✓") ? Color.secondary : Color.orange)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
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
        .sheet(item: $editing) { prompt in
            PromptEditor(existing: prompt) { updated in
                if let updated { store.update(updated) }
                editing = nil
            }
        }
        .sheet(isPresented: $creatingNew) {
            PromptEditor(existing: nil) { newOne in
                if let newOne {
                    store.add(
                        title: newOne.title,
                        symbol: newOne.symbol,
                        systemPrompt: newOne.systemPrompt
                    )
                }
                creatingNew = false
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
            try? data.write(to: url)
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
            guard response == .OK,
                  let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
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

private struct PromptEditor: View {
    let existing: CustomPrompt?
    let onSave: (CustomPrompt?) -> Void

    @State private var title: String
    @State private var symbol: String
    @State private var systemPrompt: String

    init(existing: CustomPrompt?, onSave: @escaping (CustomPrompt?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _symbol = State(initialValue: existing?.symbol ?? "wand.and.stars")
        _systemPrompt = State(initialValue: existing?.systemPrompt ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil
                 ? String(localized: "settings.prompts.editor.titleNew")
                 : String(localized: "settings.prompts.editor.titleEdit"))
                .font(.headline)

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

            Spacer(minLength: 0)

            HStack {
                Button(String(localized: "demo.sheet.cancel")) { onSave(nil) }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(String(localized: "settings.providers.save")) {
                    let trimmed = CustomPrompt(
                        id: existing?.id ?? UUID(),
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                        systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(trimmed)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }
}

// MARK: - Help

private struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                helpSection(
                    icon: "cursorarrow.rays",
                    title: String(localized: "settings.help.howTitle"),
                    body: String(localized: "settings.help.howBody")
                )
                helpSection(
                    icon: "text.bubble",
                    title: String(localized: "settings.help.promptsTitle"),
                    body: String(localized: "settings.help.promptsBody")
                )
                helpSection(
                    icon: "curlybraces",
                    title: String(localized: "settings.help.variablesTitle"),
                    body: String(localized: "settings.help.variablesBody")
                )
                helpSection(
                    icon: "square.and.arrow.up.on.square",
                    title: String(localized: "settings.help.importExportTitle"),
                    body: String(localized: "settings.help.importExportBody")
                )
                helpSection(
                    icon: "key",
                    title: String(localized: "settings.help.apiTitle"),
                    body: String(localized: "settings.help.apiBody")
                )
                helpSection(
                    icon: "exclamationmark.triangle",
                    title: String(localized: "settings.help.troubleTitle"),
                    body: String(localized: "settings.help.troubleBody")
                )
                helpSection(
                    icon: "mic",
                    title: String(localized: "settings.help.voiceTitle"),
                    body: String(localized: "settings.help.voiceBody")
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func helpSection(icon: String, title: String, body: String) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("tippi-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                Text("Tippi")
                    .font(.largeTitle)
                    .bold()
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .foregroundStyle(.secondary)

                Divider()

                Text(String(localized: "settings.about.description"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "settings.about.feature1"), systemImage: "cursorarrow.rays")
                    Label(String(localized: "settings.about.feature2"), systemImage: "key")
                    Label(String(localized: "settings.about.feature3"), systemImage: "lock.shield")
                    Label(String(localized: "settings.about.feature4"), systemImage: "text.bubble")
                    Label(String(localized: "settings.about.feature5"), systemImage: "mic")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                Text(String(localized: "settings.about.copyright"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(String(localized: "settings.about.github"), destination: URL(string: "https://github.com/miwixyz/Tippi")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Voice

private struct VoiceTab: View {
    @EnvironmentObject var permissions: PermissionsManager
    @StateObject private var modelManager = WhisperModelManager()
    @AppStorage("voice.language") private var language: String = "auto"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                microphoneSection
                modelSection
                languageSection
                advancedSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "settings.voice.mic.title"))
                    .font(.headline)
                HStack {
                    if permissions.microphoneGranted {
                        Label(String(localized: "setup.granted"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(String(localized: "setup.notGranted"), systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if !permissions.microphoneGranted {
                        Button(String(localized: "settings.voice.mic.grant")) {
                            if AudioRecorder.authorizationStatus() == .notDetermined {
                                permissions.requestMicrophonePermission()
                            } else {
                                permissions.openMicrophoneSettings()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: Model download

    private var modelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "settings.voice.model.title"))
                        .font(.headline)
                    Spacer()
                    // Overall status pill
                    if WhisperConfig.autoDetectedModelPath != nil {
                        Label(String(localized: "setup.granted"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label(String(localized: "voice.model.noModel"), systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Divider()

                ForEach(WhisperModel.catalog) { model in
                    ModelRow(model: model, manager: modelManager)
                }
            }
            .padding(6)
        }
    }

    // MARK: Language

    private var languageSection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.voice.language.title"))
                        .font(.headline)
                    Text(String(localized: "settings.voice.language.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $language) {
                    Text(String(localized: "settings.voice.language.auto")).tag("auto")
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("日本語").tag("ja")
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .onChange(of: language) { _, new in WhisperConfig.language = new }
            }
            .padding(6)
        }
    }

    // MARK: Advanced (power users)

    private var advancedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.voice.advanced.title"))
                    .font(.headline)
                Text(String(localized: "settings.voice.advanced.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    let status = WhisperConfig.autoDetectedBinaryPath
                    Image(systemName: status != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(status != nil ? Color.green : Color.orange)
                        .font(.caption)
                    Text(status ?? String(localized: "settings.voice.advanced.noBinary"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(6)
        }
    }
}

// MARK: - Model row

private struct ModelRow: View {
    let model: WhisperModel
    @ObservedObject var manager: WhisperModelManager
    @State private var isDownloaded: Bool = false

    var isThisDownloading: Bool {
        manager.downloadingModel == model.id
    }

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 18)
            } else if isThisDownloading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 18)
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text("\(model.sizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.languages)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action button or progress bar
            if isThisDownloading {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: manager.downloadProgress)
                        .frame(width: 80)
                    Button(String(localized: "voice.model.cancel")) {
                        manager.cancel()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } else if isDownloaded {
                Button(String(localized: "voice.model.delete")) {
                    manager.delete(model)
                    isDownloaded = false
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .foregroundStyle(.red)
            } else {
                Button(String(localized: "voice.model.download")) {
                    manager.download(model)
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .disabled(manager.downloadingModel != nil)
            }
        }
        .padding(.vertical, 2)
        .onAppear { isDownloaded = model.isDownloaded }
        .onChange(of: manager.downloadingModel) { _, downloading in
            // Refresh downloaded state when download completes
            if downloading == nil { isDownloaded = model.isDownloaded }
        }
    }
}
