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
            HistoryTab()
                .tabItem { Label(String(localized: "settings.tab.history"), systemImage: "clock.arrow.circlepath") }
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
    @State private var autostartIsError = false
    @AppStorage(LocalQuickActionSettings.showActionsKey) private var showLocalQuickActions: Bool = true

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
                        .foregroundStyle(autostartIsError ? Color.orange : Color.secondary)
                }
            }

            Section {
                Toggle(String(localized: "settings.general.localActions"), isOn: $showLocalQuickActions)
                Text(String(localized: "settings.general.localActions.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { refresh() }
    }

    private func refresh() {
        autostart = SMAppService.mainApp.status == .enabled
    }

    private func toggleAutostart(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                autostartStatus = String(localized: "settings.general.autostart.enabled")
            } else {
                try SMAppService.mainApp.unregister()
                autostartStatus = String(localized: "settings.general.autostart.disabled")
            }
            autostartIsError = false
        } catch {
            autostartStatus = error.localizedDescription
            autostartIsError = true
            autostart = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @EnvironmentObject var keyMonitor: GlobalKeyMonitor

    @State private var combo: KeyCombo = KeyComboStore.load()
    @State private var savedFlash = false
    @State private var translateEnabled: Bool = TranslateSettings.isEnabled
    @State private var translateCombo: KeyCombo = TranslateSettings.combo

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
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $translateEnabled) {
                            Text(String(localized: "settings.hotkeys.translate.header"))
                                .font(.headline)
                        }
                        .onChange(of: translateEnabled) { _, new in
                            TranslateSettings.isEnabled = new
                            (NSApp.delegate as? AppDelegate)?.restartTranslateHotkey()
                        }

                        Text(String(localized: "settings.hotkeys.translate.intro"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if translateEnabled {
                            HotkeyRecorderField(combo: $translateCombo)
                                .onChange(of: translateCombo) { _, new in
                                    TranslateSettings.combo = new
                                    (NSApp.delegate as? AppDelegate)?.restartTranslateHotkey()
                                }
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
    @State private var allowFallback: Bool = UserDefaults.standard.bool(forKey: "allowProviderFallback")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                defaultPickerCard
                fallbackCard
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

    private var fallbackCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $allowFallback) {
                    Text(String(localized: "settings.providers.fallback"))
                        .font(.headline)
                }
                .onChange(of: allowFallback) { _, new in
                    UserDefaults.standard.set(new, forKey: "allowProviderFallback")
                }
                Text(String(localized: "settings.providers.fallback.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
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
                        // Pre-warm MLX server when user switches to it — avoids
                        // a 30–60s wait on the first transformation.
                        if new == "mlx" {
                            MLXServerManager.autoStartIfPreferred()
                        }
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
    /// Sticky "Custom…" selection. Without this the picker would snap back to the
    /// default the moment `modelName` is cleared for editing, hiding the text
    /// field before the user can type anything.
    @State private var customModelMode: Bool = false
    @State private var saveError: String?
    /// Baseline of the last loaded values, so a sibling row's save (which bumps
    /// the shared refreshTick) doesn't reload and discard THIS row's unsaved edits.
    @State private var loadedApiKey: String = ""
    @State private var loadedModelName: String = ""
    @State private var loadedMlxPort: String = ""

    @ObservedObject private var availabilityChecker = ModelAvailabilityChecker.shared

    // MLX-only
    @ObservedObject private var mlxManager = MLXServerManager.shared
    @State private var mlxPort: String = "\(MLXServerManager.port)"
    @State private var mlxPreset: String = "custom"
    @State private var showingMLXSetup: Bool = false
    @State private var mlxIsInstalled: Bool = MLXServerManager.isInstalled

    private var isMLX: Bool { provider.id == "mlx" }

    // MARK: - MLX model presets

    struct MLXPreset: Identifiable {
        let id: String
        let label: String
        let repoID: String
    }

    /// Presets curated for Tippi's use case: fast text transformation, return
    /// only the result. Chain-of-thought / reasoning models (Qwen3.5 family,
    /// DeepSeek-R1) are deliberately excluded — they produce long internal
    /// monologues before usable output, which is wrong for a "fix this text"
    /// interaction.
    ///
    /// Each preset is labelled by the RAM tier of the target Mac, not the
    /// model's on-disk size. ⭐ marks the recommended default for speed.
    static let mlxPresets: [MLXPreset] = [
        // ── < 8 GB Mac (fastest, 2B-class, 4-bit) ───────────────────────────
        // Measured ~0.6 s warm polish, most faithful German of all presets
        // (no meaning-drift). Qwen3.5 is a thinking family — served with
        // thinking disabled so it returns only the cleaned text.
        MLXPreset(
            id: "qwen35-2b-4bit",
            label: "Qwen 3.5 2B — Fastest, faithful German (4-bit) ⭐ default",
            repoID: "mlx-community/Qwen3.5-2B-MLX-4bit"
        ),

        // ── 8 GB Mac (small, fast, 3B-class) ────────────────────────────────
        MLXPreset(
            id: "llama32-3b",
            label: "Llama 3.2 3B — Fast/Balanced",
            repoID: "mlx-community/Llama-3.2-3B-Instruct-4bit"
        ),
        MLXPreset(
            id: "phi4-mini",
            label: "Phi-4-mini 3.8B — 8 GB Mac (Microsoft, 23 languages)",
            repoID: "mlx-community/Phi-4-mini-instruct-4bit"
        ),

        // ── 16 GB Mac (mid-class, 4-8B) ─────────────────────────────────────
        MLXPreset(
            id: "gemma3-4b",
            label: "Gemma 3 4B — 16 GB Mac (Google, 140+ languages)",
            repoID: "mlx-community/gemma-3-4b-it-4bit"
        ),
        MLXPreset(
            id: "llama31-8b-4b",
            label: "Llama 3.1 8B — Quality (slower)",
            repoID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"
        ),
        MLXPreset(
            id: "qwen25-7b",
            label: "Qwen 2.5 7B — 16 GB Mac (multilingual, strong German)",
            repoID: "mlx-community/Qwen2.5-7B-Instruct-4bit"
        ),

        // ── 32 GB Mac (premium quality, 14B-class) ──────────────────────────
        MLXPreset(
            id: "qwen25-14b",
            label: "Qwen 2.5 14B — 32 GB Mac ⭐ premium",
            repoID: "mlx-community/Qwen2.5-14B-Instruct-4bit"
        ),
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

                if availabilityChecker.possiblyStale.contains(provider.id) {
                    Label(String(localized: "settings.providers.modelStale"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(String(localized: "settings.providers.modelStale.help"))
                }

                if provider.requiresAPIKey {
                    SecureField(String(localized: "settings.providers.apiKey"),
                                text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                if isMLX {
                    mlxModelPicker
                } else {
                    curatedModelPicker
                }

                // ── MLX extras ──────────────────────────────────────────────
                if isMLX {
                    if mlxIsInstalled {
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
                    } else {
                        // Not installed → friendly one-click setup card.
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "mlx.install.notInstalled"))
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button(String(localized: "mlx.install.button")) {
                                showingMLXSetup = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(8)
                        .background(.tint.opacity(0.06))
                        .cornerRadius(6)
                    }
                }
                // ────────────────────────────────────────────────────────────

                HStack {
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if savedFlash {
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
        .onChange(of: refreshTick) { _, _ in
            // Another row's save bumped the shared tick — only reload if THIS row
            // has no unsaved edits, otherwise we'd silently discard them.
            if apiKey == loadedApiKey && modelName == loadedModelName && mlxPort == loadedMlxPort {
                load()
            }
        }
        .sheet(isPresented: $showingMLXSetup, onDismiss: {
            // After the user finishes the install (or cancels), re-check disk
            // state so the UI flips from the "Install MLX" card to the normal
            // Start/Stop controls without needing an app restart.
            mlxIsInstalled = MLXServerManager.isInstalled
        }) {
            MLXSetupSheet()
        }
    }

    /// Curated dropdown for hosted providers (OpenAI/Anthropic/Gemini/
    /// Mistral/Groq). Falls back to a free-form text field for Ollama
    /// (whatever the user has pulled locally) and for unknown providers.
    /// The "Custom…" sentinel always lets the user type a model ID that
    /// isn't in the curated list (new releases between Tippi updates).
    @ViewBuilder
    private var curatedModelPicker: some View {
        let presets = ProviderModelPresets.presets(for: provider.id)

        if presets.isEmpty {
            HStack {
                Text(String(localized: "settings.providers.model"))
                    .font(.caption)
                    .frame(width: 60, alignment: .leading)
                TextField(provider.defaultModel, text: $modelName)
                    .textFieldStyle(.roundedBorder)
            }
        } else {
            // A stored model that isn't a preset means the user typed a custom id.
            let storedIsCustom = !modelName.isEmpty && !presets.contains(where: { $0.id == modelName })
            let showCustom = customModelMode || storedIsCustom
            let pickerSelection = Binding<String>(
                get: {
                    if showCustom { return "__custom__" }
                    return modelName.isEmpty ? provider.defaultModel : modelName
                },
                set: { newValue in
                    if newValue == "__custom__" {
                        // Enter custom mode and keep it sticky. Clear the field only
                        // when coming from a preset, so re-selecting Custom doesn't
                        // wipe an id the user already typed.
                        if !storedIsCustom { modelName = "" }
                        customModelMode = true
                    } else {
                        customModelMode = false
                        modelName = newValue
                    }
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "settings.providers.model"))
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: pickerSelection) {
                        ForEach(presets) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                        Divider()
                        Text(String(localized: "settings.providers.customModel")).tag("__custom__")
                    }
                    .labelsHidden()
                }
                if showCustom {
                    TextField(provider.defaultModel, text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.leading, 60)
                        .font(.caption)
                }
            }
        }
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
            if let match = Self.mlxPresets.first(where: { $0.repoID == modelName || $0.repoID == (UserDefaults.standard.string(forKey: "defaultModel.mlx") ?? MLXServerManager.defaultModel) }) {
                mlxPreset = match.id
                modelName = match.repoID
            } else {
                mlxPreset = "custom"
                if modelName.isEmpty { modelName = MLXServerManager.model }
            }
        }
        // Record the loaded baseline so cross-row refreshes can detect edits.
        loadedApiKey = apiKey
        loadedModelName = modelName
        loadedMlxPort = mlxPort
    }

    private func save() {
        // Validate the MLX port up-front so an invalid entry never receives a
        // false "Saved" confirmation while the change is silently dropped.
        var validatedPort: Int?
        if isMLX {
            guard let p = Int(mlxPort.trimmingCharacters(in: .whitespaces)), (1...65535).contains(p) else {
                saveError = String(localized: "settings.providers.mlx.portInvalid")
                return
            }
            validatedPort = p
        }

        if provider.requiresAPIKey {
            // A swallowed keychain error would let the UI flash "Saved" while the
            // key was never persisted — surface it instead.
            do {
                try KeychainStore.setAPIKey(apiKey, for: provider.id)
            } catch {
                saveError = String(localized: "settings.providers.keychainSaveFailed")
                NSLog("Tippi: keychain save failed for \(provider.id): \(error.localizedDescription)")
                return
            }
        }
        saveError = nil

        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty {
            UserDefaults.standard.removeObject(forKey: "defaultModel.\(provider.id)")
        } else {
            UserDefaults.standard.set(trimmedModel, forKey: "defaultModel.\(provider.id)")
        }
        if isMLX, let p = validatedPort {
            let modelChanged = !trimmedModel.isEmpty && trimmedModel != MLXServerManager.model
            let portChanged  = p != MLXServerManager.port
            let wasRunning   = mlxManager.state.isRunning
            if !trimmedModel.isEmpty { MLXServerManager.model = trimmedModel }
            MLXServerManager.port = p
            // Auto-restart with new config when settings changed and server was up —
            // user shouldn't have to click Start manually after every save.
            if (modelChanged || portChanged) && wasRunning {
                Task { try? await mlxManager.restart() }
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
        case "scaleway":  return String(localized: "settings.providers.hint.scaleway")
        case "groq":      return String(localized: "settings.providers.hint.groq")
        case "kimi":      return String(localized: "settings.providers.hint.kimi")
        case "nebius":    return String(localized: "settings.providers.hint.nebius")
        case "openrouter": return String(localized: "settings.providers.hint.openrouter")
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
                        Text(String(localized: "settings.prompts.builtIn.overrideHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(DemoPrompt.builtIn) { p in
                            BuiltInPromptRow(prompt: p)
                            Divider()
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
                    store.add(newOne)
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

/// One row in the built-in prompts list: title (read-only, can't edit the
/// wording of a built-in) plus a per-prompt provider/model override. Exists
/// because a global default provider that's great for short dictation polish
/// (small local model, fast) can be hopeless on a long prompt like "Improve"
/// run against a multi-paragraph business email — reproduced 2026-09-01:
/// MLX Qwen3.5 2B returned such an email completely unchanged. Rather than
/// force a bigger/cloud model globally, this pins one prompt to a different
/// provider without touching everyone else's default.
private struct BuiltInPromptRow: View {
    let prompt: DemoPrompt

    @State private var providerOverride: String
    @State private var modelOverride: String

    init(prompt: DemoPrompt) {
        self.prompt = prompt
        _providerOverride = State(initialValue: PromptProviderOverride.providerID(for: prompt.id))
        _modelOverride = State(initialValue: PromptProviderOverride.modelOverride(for: prompt.id))
    }

    private static let useActive = "__active__"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: prompt.symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                Text(prompt.title)
                Spacer()
                Picker("", selection: providerBinding) {
                    Text(String(localized: "settings.voice.dictation.postProcess.providerActive"))
                        .tag(Self.useActive)
                    Divider()
                    ForEach(LLMRouter.allProviders, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            if !providerOverride.isEmpty {
                let modelPresets = ProviderModelPresets.presets(for: providerOverride)
                if !modelPresets.isEmpty {
                    HStack {
                        Spacer().frame(width: 22)
                        Text(String(localized: "settings.providers.model"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: modelBinding) {
                            ForEach(modelPresets) { preset in
                                Text(preset.label).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { providerOverride.isEmpty ? Self.useActive : providerOverride },
            set: { new in
                let value = (new == Self.useActive) ? "" : new
                providerOverride = value
                PromptProviderOverride.setProviderID(value, for: prompt.id)
                if !value.isEmpty, let fastest = ProviderModelPresets.defaultPolishModel(for: value) {
                    modelOverride = fastest
                    PromptProviderOverride.setModelOverride(fastest, for: prompt.id)
                } else {
                    modelOverride = ""
                    PromptProviderOverride.setModelOverride("", for: prompt.id)
                }
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { modelOverride },
            set: { new in
                modelOverride = new
                PromptProviderOverride.setModelOverride(new, for: prompt.id)
            }
        )
    }
}

private struct PromptEditor: View {
    let existing: CustomPrompt?
    let onSave: (CustomPrompt?) -> Void

    private enum Mode: Hashable { case single, chain }

    @State private var title: String
    @State private var symbol: String
    @State private var systemPrompt: String
    @State private var mode: Mode
    @State private var pipeline: [String]

    init(existing: CustomPrompt?, onSave: @escaping (CustomPrompt?) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _symbol = State(initialValue: existing?.symbol ?? "wand.and.stars")
        _systemPrompt = State(initialValue: existing?.systemPrompt ?? "")
        _mode = State(initialValue: (existing?.isChain ?? false) ? .chain : .single)
        _pipeline = State(initialValue: existing?.pipeline ?? [])
    }

    /// Prompts that can be used as chain steps: every non-chain prompt except
    /// the one being edited (a chain can't reference itself, and chain-in-chain
    /// is out of scope).
    private var availableSteps: [DemoPrompt] {
        let selfID = existing.map { "custom-\($0.id.uuidString)" }
        return DemoPrompt.all.filter { !$0.isChain && $0.id != selfID }
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

            Picker(String(localized: "settings.prompts.editor.mode"), selection: $mode) {
                Text(String(localized: "settings.prompts.editor.mode.single")).tag(Mode.single)
                Text(String(localized: "settings.prompts.editor.mode.chain")).tag(Mode.chain)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .single {
                singleEditor
            } else {
                chainEditor
            }

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
                        systemPrompt: mode == .single
                            ? systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            : "",
                        pipeline: mode == .chain ? pipeline : nil
                    )
                    onSave(trimmed)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
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

// MARK: - Help

private struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                helpSection(
                    icon: "star.circle",
                    title: String(localized: "settings.help.whatsNewTitle"),
                    body: String(localized: "settings.help.whatsNewBody")
                )
                helpSection(
                    icon: "cursorarrow.rays",
                    title: String(localized: "settings.help.howTitle"),
                    body: String(localized: "settings.help.howBody")
                )
                helpSection(
                    icon: "keyboard",
                    title: String(localized: "settings.help.instructTitle"),
                    body: String(localized: "settings.help.instructBody")
                )
                helpSection(
                    icon: "sparkles",
                    title: String(localized: "settings.help.previewTitle"),
                    body: String(localized: "settings.help.previewBody")
                )
                helpSection(
                    icon: "text.bubble",
                    title: String(localized: "settings.help.promptsTitle"),
                    body: String(localized: "settings.help.promptsBody")
                )
                helpSection(
                    icon: "arrow.right.circle",
                    title: String(localized: "settings.help.chainsTitle"),
                    body: String(localized: "settings.help.chainsBody")
                )
                helpSection(
                    icon: "bolt",
                    title: String(localized: "settings.help.localActionsTitle"),
                    body: String(localized: "settings.help.localActionsBody")
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
                    icon: "wand.and.stars.inverse",
                    title: String(localized: "settings.help.pickModelTitle"),
                    body: String(localized: "settings.help.pickModelBody")
                )
                helpSection(
                    icon: "cpu",
                    title: String(localized: "settings.help.mlxTitle"),
                    body: String(localized: "settings.help.mlxBody")
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
                helpSection(
                    icon: "character.bubble",
                    title: String(localized: "settings.help.translateTitle"),
                    body: String(localized: "settings.help.translateBody")
                )
                helpSection(
                    icon: "magnifyingglass",
                    title: String(localized: "settings.help.commandPaletteTitle"),
                    body: String(localized: "settings.help.commandPaletteBody")
                )
                helpSection(
                    icon: "clock.arrow.circlepath",
                    title: String(localized: "settings.help.historyTitle"),
                    body: String(localized: "settings.help.historyBody")
                )
                helpSection(
                    icon: "link",
                    title: String(localized: "settings.help.linksTitle"),
                    body: String(localized: "settings.help.linksBody")
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
                    // Parse the body as inline Markdown so [label](url) renders
                    // as a clickable link. Falls back to plain text on parse
                    // failure. `inlineOnlyPreservingWhitespace` keeps paragraph
                    // breaks intact (the bodies use \n\n between paragraphs).
                    Text(markdownAttributedString(from: body))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(6)
        }
    }

    /// Convert the help-body string into an AttributedString with Markdown
    /// links activated. The Foundation parser is strict — if it fails for
    /// any reason, we fall back to the verbatim text rather than crashing
    /// or hiding content.
    private func markdownAttributedString(from body: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: body, options: options) {
            return attributed
        }
        return AttributedString(body)
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

                Text(String(localized: "settings.about.acknowledgements"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Link(String(localized: "settings.about.github"),
                         destination: URL(string: "https://github.com/miwixyz/Tippi")!)
                    Text("·").foregroundStyle(.tertiary)
                    Link(String(localized: "settings.about.landingPage"),
                         destination: URL(string: "https://miwixyz.github.io/Tippi/")!)
                    Text("·").foregroundStyle(.tertiary)
                    Link(String(localized: "settings.about.onePager"),
                         destination: URL(string: "https://github.com/miwixyz/Tippi/blob/main/docs/ONE-PAGER.md")!)
                }
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
    @State private var muteSystemAudio: Bool = AudioRecorder.muteSystemAudioDuringRecording
    @State private var dictationEnabled: Bool = DictationSettings.isEnabled
    @State private var dictationCombo: KeyCombo = DictationSettings.combo
    @State private var dictationPostProcess: Bool = DictationSettings.postProcessEnabled
    @State private var dictationPostProcessPrompt: String = DictationSettings.postProcessPrompt
    @State private var dictationPolishProvider: String = DictationSettings.postProcessProviderOverride
    @State private var dictationPolishModel: String = DictationSettings.postProcessModelOverride
    @State private var engine: String = SpeechEngine.current.rawValue
    @ObservedObject private var parakeetStatus = ParakeetStatus.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                microphoneSection
                systemAudioSection
                engineSection
                modelSection
                languageSection
                dictationSection
                advancedSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Engine (spike: Parakeet v3 via FluidAudio)

    private var engineSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.voice.engine.title"))
                            .font(.headline)
                        Text(String(localized: "settings.voice.engine.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Picker("", selection: $engine) {
                        Text("Whisper").tag(SpeechEngine.Kind.whisper.rawValue)
                        Text("Parakeet v3 (Beta)").tag(SpeechEngine.Kind.parakeet.rawValue)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .onChange(of: engine) { _, new in
                        SpeechEngine.current = SpeechEngine.Kind(rawValue: new) ?? .whisper
                        parakeetStatus.refreshFromDisk()
                        // Switching to Parakeet can make dictation available
                        // without a Whisper model — re-register the hot key.
                        (NSApp.delegate as? AppDelegate)?.restartDictationHotkey()
                    }
                }

                if engine == SpeechEngine.Kind.parakeet.rawValue {
                    Divider()
                    parakeetStatusRow
                }
            }
            .padding(6)
        }
        .onAppear { parakeetStatus.refreshFromDisk() }
    }

    @ViewBuilder
    private var parakeetStatusRow: some View {
        HStack(spacing: 8) {
            switch parakeetStatus.phase {
            case .notDownloaded:
                Label(String(localized: "settings.voice.engine.status.notDownloaded"),
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Button(String(localized: "settings.voice.engine.download")) {
                    Task { await ParakeetTranscriber.shared.prewarm() }
                }
                .controlSize(.small)
            case .downloading(let fraction):
                Text(String(localized: "settings.voice.engine.status.downloading"))
                    .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            case .ready:
                Label(String(localized: "settings.voice.engine.status.ready"),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
            case .failed(let message):
                Label(message, systemImage: "xmark.circle")
                    .font(.caption)
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

    // MARK: Dictation hot key

    private var dictationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "settings.voice.dictation.title"))
                    .font(.headline)
                Text(String(localized: "settings.voice.dictation.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(String(localized: "settings.voice.dictation.enable"), isOn: $dictationEnabled)
                    .onChange(of: dictationEnabled) { _, new in
                        DictationSettings.isEnabled = new
                        (NSApp.delegate as? AppDelegate)?.restartDictationHotkey()
                    }

                if dictationEnabled {
                    if SpeechEngine.current == .whisper && !WhisperConfig.isConfigured {
                        Label(String(localized: "settings.voice.dictation.needsModel"),
                              systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HotkeyRecorderField(combo: $dictationCombo)
                        .onChange(of: dictationCombo) { _, new in
                            DictationSettings.combo = new
                            (NSApp.delegate as? AppDelegate)?.restartDictationHotkey()
                        }

                    Divider().padding(.vertical, 4)

                    Toggle(String(localized: "settings.voice.dictation.postProcess.enable"),
                           isOn: $dictationPostProcess)
                        .onChange(of: dictationPostProcess) { _, new in
                            DictationSettings.postProcessEnabled = new
                        }

                    Text(String(localized: "settings.voice.dictation.postProcess.body"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if dictationPostProcess {
                        polishProviderPicker

                        Text(String(localized: "settings.voice.dictation.postProcess.promptLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $dictationPostProcessPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100, maxHeight: 180)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .onChange(of: dictationPostProcessPrompt) { _, new in
                                DictationSettings.postProcessPrompt = new
                            }
                        Button(String(localized: "settings.voice.dictation.postProcess.reset")) {
                            dictationPostProcessPrompt = DictationSettings.defaultPostProcessPrompt
                            DictationSettings.postProcessPrompt = DictationSettings.defaultPostProcessPrompt
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(6)
        }
    }

    /// Provider+model override for the polish step only. Default is
    /// "use the same provider as everything else"; switching to Groq +
    /// Llama 3.1 8B Instant typically takes polish latency from 2–5 s
    /// (OpenAI/MLX) to well under 1 s.
    private var polishProviderPicker: some View {
        // Sentinel value for "no override" since Picker can't bind to nil.
        let useActive = "__active__"
        let providerBinding = Binding<String>(
            get: { dictationPolishProvider.isEmpty ? useActive : dictationPolishProvider },
            set: { new in
                let value = (new == useActive) ? "" : new
                dictationPolishProvider = value
                DictationSettings.postProcessProviderOverride = value
                // Auto-pick the fastest non-reasoning model on the new provider.
                if !value.isEmpty,
                   let fastest = ProviderModelPresets.defaultPolishModel(for: value) {
                    dictationPolishModel = fastest
                    DictationSettings.postProcessModelOverride = fastest
                } else {
                    dictationPolishModel = ""
                    DictationSettings.postProcessModelOverride = ""
                }
            }
        )

        let modelPresets = ProviderModelPresets.presets(for: dictationPolishProvider)
        let modelBinding = Binding<String>(
            get: { dictationPolishModel },
            set: { new in
                dictationPolishModel = new
                DictationSettings.postProcessModelOverride = new
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "settings.voice.dictation.postProcess.providerLabel"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: providerBinding) {
                    Text(String(localized: "settings.voice.dictation.postProcess.providerActive"))
                        .tag(useActive)
                    Divider()
                    ForEach(LLMRouter.allProviders, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
            }

            if !dictationPolishProvider.isEmpty && !modelPresets.isEmpty {
                HStack {
                    Text(String(localized: "settings.providers.model"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: modelBinding) {
                        ForEach(modelPresets) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
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

    // MARK: System audio

    private var systemAudioSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "settings.voice.systemAudio.title"))
                    .font(.headline)
                Toggle(String(localized: "settings.voice.systemAudio.enable"), isOn: $muteSystemAudio)
                    .onChange(of: muteSystemAudio) { _, new in
                        AudioRecorder.muteSystemAudioDuringRecording = new
                    }
                Text(String(localized: "settings.voice.systemAudio.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
