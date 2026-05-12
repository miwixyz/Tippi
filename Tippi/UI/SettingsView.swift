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

                HStack {
                    Text(String(localized: "settings.providers.model"))
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    TextField(provider.defaultModel, text: $modelName)
                        .textFieldStyle(.roundedBorder)
                }

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
        default:          return ""
        }
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @StateObject private var store = CustomPromptStore.shared
    @State private var editing: CustomPrompt?
    @State private var creatingNew: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "settings.prompts.custom"))
                                .font(.headline)
                            Spacer()
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
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    icon: "key",
                    title: String(localized: "settings.help.apiTitle"),
                    body: String(localized: "settings.help.apiBody")
                )
                helpSection(
                    icon: "exclamationmark.triangle",
                    title: String(localized: "settings.help.troubleTitle"),
                    body: String(localized: "settings.help.troubleBody")
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
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Tippi")
                    .font(.largeTitle)
                    .bold()
                Text("Version 1.0.0")
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
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                Text(String(localized: "settings.about.copyright"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
