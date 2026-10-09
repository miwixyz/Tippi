// swiftlint:disable file_length
// Bestand 2026-09-25, Sperrklinke: 2532 Zeilen, alle Settings-Tabs in einer Datei.
// Aufteilen ist eigene Arbeit, kein Lint-Nebenprodukt.

import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsTab = .general
    @ObservedObject private var navigation = SettingsNavigation.shared

    /// Sidebar navigation rather than a row of tabs.
    ///
    /// Nine top tabs in a window fixed at 640×580 had become unreadable — the
    /// labels truncate, and a long pane (Voice, Providers) scrolls inside a box
    /// that cannot grow. This is the layout macOS itself uses for System
    /// Settings: a grouped list on the left, one pane on the right, and a
    /// window the user can size. Same panes, same content, nothing removed.
    ///
    /// Groups mirror how the panes are actually used: everyday configuration,
    /// then the text/AI machinery, then things looked at occasionally.
    private static let sidebarGroups: [[SettingsTab]] = [
        [.general, .permissions, .hotkeys, .voice],
        [.providers, .prompts, .snippets, .autocomplete],
        [.history, .help, .about],
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Array(Self.sidebarGroups.enumerated()), id: \.offset) { index, group in
                    Section {
                        ForEach(group, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.symbol).tag(tab)
                        }
                    } header: {
                        // Dividing lines, not headings: the groups exist to
                        // break up a list of nine, and inventing category names
                        // for them would add words without adding meaning.
                        if index > 0 { Divider() }
                    }
                }
            }
            // Ideal 225, not 190 (2026-09-28): „Wörterbuch & Snippets" is 141 pt
            // wide at 13 pt, „Autovervollständigung" 135 pt; with icon, spacing
            // and the list's insets (~65–80 pt) a 190-pt column truncated them.
            // Calculated, not measured on screen.
            .navigationSplitViewColumnWidth(min: 170, ideal: 225, max: 260)
        } detail: {
            // Every pane stays alive; only visibility changes.
            //
            // A `switch` here reads better but destroys the unselected panes,
            // and that broke two things the old TabView had guaranteed. A
            // Whisper model download (hundreds of MB) is owned by VoiceTab's
            // @StateObject — leaving the pane deallocated it, the transfer ran
            // to completion anyway and the finished file was deleted in the
            // completion handler because `self` was gone: no progress, no
            // error, just "not downloaded". And ProviderRow deliberately keeps
            // unsaved edits in @State, so an API key pasted but not yet saved
            // was silently reverted by navigating away and back.
            //
            // Panes are cheap; the panes with real work in them are not
            // reconstructible. Keeping them mounted restores the old contract.
            ZStack {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    pane(for: tab)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .opacity(tab == selection ? 1 : 0)
                        // `.disabled` rather than `.allowsHitTesting`: the
                        // latter only blocks the mouse. Every hidden pane still
                        // holds real text fields (eleven API keys, the Help
                        // search, the MLX port), and nothing else takes them out
                        // of the key-view loop — Tab could move focus into a
                        // field nobody can see, with keystrokes vanishing into
                        // it. Disabling leaves @StateObject work and unsaved
                        // @State edits untouched, which is the whole point of
                        // keeping the panes mounted.
                        .disabled(tab != selection)
                        .accessibilityHidden(tab != selection)
                }
            }
            .navigationTitle(selection.title)
            // A hotkey recorder arms a local NSEvent monitor and only tears it
            // down in `.onDisappear`. No pane disappears any more, so an armed
            // recorder used to survive the switch and keep swallowing keyDowns:
            // pressing ⌘V in an API key field silently rebound the global
            // hotkey to ⌘V instead of pasting, with no visible recording state
            // because the pane was hidden.
            .onChange(of: selection) { _, _ in RecorderMonitorStore.release() }
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 520, idealHeight: 640)
        // The Settings window is created once and just reordered front on
        // repeat opens (AppDelegate.showSettingsWindow), so `.onAppear`
        // alone would miss a second "jump to Help" request — this fires on
        // every new request regardless of window lifecycle.
        .onReceive(navigation.$pendingTab.compactMap { $0 }) { tab in
            selection = tab
            navigation.pendingTab = nil
        }
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:   GeneralSettingsTab()
        case .permissions: PermissionsTab()
        case .hotkeys:   HotkeysTab()
        case .providers: ProvidersTab()
        case .prompts:   PromptsTab()
        case .snippets:  SnippetsTab()
        case .autocomplete:
            if let autocomplete = AppDelegate.shared?.autocomplete {
                AutocompleteSettingsTab(controller: autocomplete)
            }
        case .voice:     VoiceTab()
        case .history:   HistoryTab()
        case .help:      HelpTab()
        case .about:     AboutTab()
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var autostart: Bool = false
    @State private var autostartStatus: String = ""
    @State private var autostartIsError = false
    @AppStorage(LocalQuickActionSettings.showActionsKey) private var showLocalQuickActions: Bool = true
    @AppStorage(SelectionPopupSettings.enabledKey) private var selectionPopupEnabled: Bool = false
    @State private var selectionPopupPosition: SelectionPopupPosition = SelectionPopupSettings.position
    @State private var appearanceMode: AppearanceSettings.Mode = AppearanceSettings.mode

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "settings.general.appearance"), selection: $appearanceMode) {
                    Text(String(localized: "settings.general.appearance.system")).tag(AppearanceSettings.Mode.system)
                    Text(String(localized: "settings.general.appearance.light")).tag(AppearanceSettings.Mode.light)
                    Text(String(localized: "settings.general.appearance.dark")).tag(AppearanceSettings.Mode.dark)
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) { _, new in
                    AppearanceSettings.mode = new
                }
            }

            Section {
                // A binding that acts on user clicks only. `onChange` also fired
                // on the programmatic reset after a failed register (the real
                // error got overwritten by unregister's message) and on the
                // refresh in onAppear (audit 2026-09-27).
                Toggle(String(localized: "settings.general.autostart"),
                       isOn: Binding(get: { autostart }, set: { toggleAutostart($0) }))
                if !autostartStatus.isEmpty {
                    Text(autostartStatus)
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(autostartIsError ? Color.orange : Color.secondary)
                }
            }

            Section {
                Toggle(String(localized: "settings.general.localActions"), isOn: $showLocalQuickActions)
                Text(String(localized: "settings.general.localActions.hint"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
            }

            CurrencyFavoritesSection()

            Section {
                Toggle(String(localized: "settings.general.selectionPopup"), isOn: $selectionPopupEnabled)
                    .onChange(of: selectionPopupEnabled) { _, _ in
                        AppDelegate.shared?.restartSelectionPopupEngine()
                    }
                Text(String(localized: "settings.general.selectionPopup.hint"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)

                if selectionPopupEnabled {
                    Picker(String(localized: "settings.general.selectionPopup.position"), selection: $selectionPopupPosition) {
                        Text(String(localized: "settings.general.selectionPopup.position.below")).tag(SelectionPopupPosition.below)
                        Text(String(localized: "settings.general.selectionPopup.position.above")).tag(SelectionPopupPosition.above)
                        Text(String(localized: "settings.general.selectionPopup.position.right")).tag(SelectionPopupPosition.right)
                        Text(String(localized: "settings.general.selectionPopup.position.left")).tag(SelectionPopupPosition.left)
                    }
                    .onChange(of: selectionPopupPosition) { _, new in
                        SelectionPopupSettings.position = new
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollContentBackground(.hidden)
        .onAppear { refresh() }
    }

    private func refresh() {
        autostart = SMAppService.mainApp.status == .enabled
    }

    private func toggleAutostart(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // From the real status, not the requested one: `.requiresApproval`
            // left the switch off but the text said "enabled" (review 2026-09-27).
            switch SMAppService.mainApp.status {
            case .enabled:          autostartStatus = String(localized: "settings.general.autostart.enabled")
            case .requiresApproval: autostartStatus = String(localized: "settings.general.autostart.requiresApproval")
            default:                autostartStatus = String(localized: "settings.general.autostart.disabled")
            }
            autostartIsError = false
        } catch {
            autostartStatus = error.localizedDescription
            autostartIsError = true
        }
        autostart = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @EnvironmentObject var keyMonitor: GlobalKeyMonitor
    /// Observed, not `AXIsProcessTrusted()` directly: a bare function call
    /// never re-renders the view, so the warning stayed on screen after the
    /// permission had already been granted.
    @EnvironmentObject var permissions: PermissionsManager

    /// The three secondary hot keys live on the AppDelegate. They are all the
    /// same type, so they cannot be injected via `@EnvironmentObject` (one value
    /// per type) — observed directly instead. The managers are `let` properties
    /// on the delegate and outlive this view, so the references stay valid.
    @ObservedObject private var translateHotkey: HotkeyManager
    @ObservedObject private var emojiHotkey: HotkeyManager
    @ObservedObject private var notesHotkey: HotkeyManager
    @ObservedObject private var screenOCRHotkey: HotkeyManager

    init() {
        // A missing delegate cannot happen while Settings is on screen, but a
        // detached fallback keeps this non-crashing (and visibly inactive).
        let delegate = AppDelegate.shared
        _translateHotkey = ObservedObject(
            wrappedValue: delegate?.translateHotkeyManager ?? HotkeyManager(id: 903))
        _emojiHotkey = ObservedObject(
            wrappedValue: delegate?.emojiHotkeyManager ?? HotkeyManager(id: 904))
        _screenOCRHotkey = ObservedObject(
            wrappedValue: delegate?.screenOCRHotkeyManager ?? HotkeyManager(id: 906))
        _notesHotkey = ObservedObject(
            wrappedValue: delegate?.notesHotkeyManager ?? HotkeyManager(id: 905))
    }

    @State private var combo: KeyCombo = KeyComboStore.load()
    @State private var savedFlash = false
    @State private var translateEnabled: Bool = TranslateSettings.isEnabled
    @State private var translateCombo: KeyCombo = TranslateSettings.combo
    @State private var emojiPickerEnabled: Bool = EmojiSettings.isPickerEnabled
    @State private var emojiCombo: KeyCombo = EmojiSettings.combo
    @State private var notesEnabled: Bool = NotesSettings.isEnabled

    @State private var screenOCREnabled = ScreenOCRSettings.isEnabled

    @State private var screenOCRCombo = ScreenOCRSettings.combo

    @State private var screenOCRConceal = ScreenOCRSettings.concealFromClipboardHistory
    @State private var screenOCRJoin = ScreenOCRSettings.joinLines
    @State private var notesCombo: KeyCombo = NotesSettings.combo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "settings.hotkeys.header"))
                            .font(FamilyTheme.font(.headline))
                        Text(String(localized: "settings.hotkeys.intro"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)

                        HotkeyRecorderField(combo: $combo)
                            .onChange(of: combo) { _, new in
                                KeyComboStore.save(new)
                                keyMonitor.update(combo: new)
                                AppDelegate.shared?.applyMainHotkeyChange()
                                savedFlash = true
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    savedFlash = false
                                }
                            }

                        Text(String(localized: "settings.hotkeys.restartHint"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)

                        HStack {
                            Button(String(localized: "settings.hotkeys.reset")) {
                                combo = .default
                            }
                            .buttonStyle(.bordered)
                            Button(String(localized: "settings.hotkeys.testTrigger")) {
                                AppDelegate.shared?.triggerManually()
                            }
                            .buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
                            Spacer()
                            if savedFlash {
                                Text(String(localized: "settings.providers.savedFlash"))
                                    .font(FamilyTheme.font(.caption))
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
                            .font(FamilyTheme.font(.headline))
                        Text(String(localized: "settings.hotkeys.macOSBody"))
                            .font(FamilyTheme.font(.caption))
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

                // Moved here from the Dictation pane (2026-09-28): every hot key in one place.
                GroupBox { DictationHotkeySection().padding(6) }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $translateEnabled) {
                            Text(String(localized: "settings.hotkeys.translate.header"))
                                .font(FamilyTheme.font(.headline))
                        }
                        .onChange(of: translateEnabled) { _, new in
                            TranslateSettings.isEnabled = new
                            AppDelegate.shared?.restartTranslateHotkey()
                        }

                        Text(String(localized: "settings.hotkeys.translate.intro"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if translateEnabled {
                            HotkeyRecorderField(combo: $translateCombo)
                                .onChange(of: translateCombo) { _, new in
                                    TranslateSettings.combo = new
                                    AppDelegate.shared?.restartTranslateHotkey()
                                }
                            hotkeyControls(
                                manager: translateHotkey,
                                combo: translateCombo,
                                reset: { translateCombo = .translateDefault },
                                test: { AppDelegate.shared?.triggerTranslatePanel() }
                            )
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $emojiPickerEnabled) {
                            Text(String(localized: "settings.hotkeys.emoji.header"))
                                .font(FamilyTheme.font(.headline))
                        }
                        .onChange(of: emojiPickerEnabled) { _, new in
                            EmojiSettings.isPickerEnabled = new
                            AppDelegate.shared?.restartEmojiHotkey()
                        }

                        Text(String(localized: "settings.hotkeys.emoji.intro"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if emojiPickerEnabled {
                            HotkeyRecorderField(combo: $emojiCombo)
                                .onChange(of: emojiCombo) { _, new in
                                    EmojiSettings.combo = new
                                    AppDelegate.shared?.restartEmojiHotkey()
                                }
                            hotkeyControls(
                                manager: emojiHotkey,
                                combo: emojiCombo,
                                reset: { emojiCombo = .emojiDefault },
                                test: { AppDelegate.shared?.triggerEmojiPicker() }
                            )
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $notesEnabled) {
                            Text(String(localized: "settings.hotkeys.notes.header"))
                                .font(FamilyTheme.font(.headline))
                        }
                        .onChange(of: notesEnabled) { _, new in
                            NotesSettings.isEnabled = new
                            AppDelegate.shared?.restartNotesHotkey()
                        }

                        Text(String(localized: "settings.hotkeys.notes.intro"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if notesEnabled {
                            HotkeyRecorderField(combo: $notesCombo)
                                .onChange(of: notesCombo) { _, new in
                                    NotesSettings.combo = new
                                    AppDelegate.shared?.restartNotesHotkey()
                                }
                            hotkeyControls(
                                manager: notesHotkey,
                                combo: notesCombo,
                                reset: { notesCombo = .notesDefault },
                                test: { AppDelegate.shared?.showNotesWindow() }
                            )
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $screenOCREnabled) {
                            Text(String(localized: "settings.ocr.title")).font(FamilyTheme.font(.headline))
                        }
                        .onChange(of: screenOCREnabled) { _, new in
                            ScreenOCRSettings.isEnabled = new
                            AppDelegate.shared?.restartScreenOCRHotkey()
                        }

                        Text(String(localized: "settings.ocr.body"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(String(localized: "settings.ocr.permission"))
                            .font(FamilyTheme.font(.caption2))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if screenOCREnabled {
                            HotkeyRecorderField(combo: $screenOCRCombo)
                                .onChange(of: screenOCRCombo) { _, new in
                                    ScreenOCRSettings.combo = new
                                    AppDelegate.shared?.restartScreenOCRHotkey()
                                }
                            hotkeyControls(
                                manager: screenOCRHotkey,
                                combo: screenOCRCombo,
                                reset: { screenOCRCombo = KeyCombo(keyCode: 19,
                                                                   modifiers: [.option, .command]) },
                                test: { AppDelegate.shared?.beginScreenOCR() }
                            )

                            Divider()

                            Toggle(String(localized: "settings.ocr.joinLines"), isOn: $screenOCRJoin)
                                .onChange(of: screenOCRJoin) { _, new in
                                    ScreenOCRSettings.joinLines = new
                                }
                            Text(String(localized: "settings.ocr.joinLinesHint"))
                                .font(FamilyTheme.font(.caption2))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Toggle(String(localized: "settings.ocr.conceal"),
                                   isOn: $screenOCRConceal)
                                .onChange(of: screenOCRConceal) { _, new in
                                    ScreenOCRSettings.concealFromClipboardHistory = new
                                }
                            Text(String(localized: "settings.ocr.concealHint"))
                                .font(FamilyTheme.font(.caption2))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "settings.hotkeys.tipHeader"))
                            .font(FamilyTheme.font(.headline))
                        Text(String(localized: "settings.hotkeys.tip1"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "settings.hotkeys.tip2"))
                            .font(FamilyTheme.font(.caption))
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
        statusLine(error: keyMonitor.lastError,
                   isActive: keyMonitor.isActive,
                   combo: keyMonitor.combo.displayString)
    }

    /// Shared status line for every hot key. Deliberately takes plain values
    /// instead of a manager: the main trigger is a `GlobalKeyMonitor`, the three
    /// secondary ones are `HotkeyManager` — different types, same three facts.
    ///
    /// Showing `lastError` here is the whole point: `RegisterEventHotKey`
    /// failures were recorded and then thrown away, so a hot key that never
    /// registered looked identical to one that worked.
    @ViewBuilder
    private func statusLine(
        error: String?,
        isActive: Bool,
        combo: String,
        inactiveText: String = String(localized: "settings.hotkeys.inactive")
    ) -> some View {
        if let error {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                // A message telling the user to go grant a permission is not
                // enough — it has to be one click away. Only shown when the
                // permission is actually missing, so it cannot become noise.
                if !permissions.accessibilityGranted {
                    Button(String(localized: "settings.permissions.grant")) {
                        // No `NSApp.delegate as? AppDelegate` detour: a failing
                        // cast made this button do nothing at all, silently.
                        let url = URL(string: "x-apple.systempreferences:"
                            + "com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                        // System Settings opens BEHIND Tippi (and does not move
                        // at all when already open), which reads as "the button
                        // is broken". Pull it to the front explicitly.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            NSWorkspace.shared.runningApplications
                                .first { $0.bundleIdentifier == "com.apple.systempreferences" }?
                                .activate(options: [.activateAllWindows])
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
                    .controlSize(.small)
                }
            }
        } else if isActive {
            Label(
                String(format: String(localized: "settings.hotkeys.active"), combo),
                systemImage: "checkmark.circle.fill"
            )
            .font(FamilyTheme.font(.caption))
            .foregroundStyle(.green)
        } else {
            Label(inactiveText, systemImage: "pause.circle")
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)
        }
    }

    /// Reset + test + status, identical for all three secondary hot keys.
    @ViewBuilder
    private func hotkeyControls(
        manager: HotkeyManager,
        combo: KeyCombo,
        reset: @escaping () -> Void,
        test: @escaping () -> Void
    ) -> some View {
        // Same layout and button styles as the main hot key above — bordered
        // reset, prominent test, default control size. Anything else reads as
        // a different kind of control.
        HStack {
            // NOT `settings.hotkeys.reset` — that label has the main trigger's
            // combo (⌥⌘T) baked in and would be wrong on every other hot key.
            Button(String(localized: "settings.hotkeys.reset.generic"), action: reset)
                .buttonStyle(.bordered)
            Button(String(localized: "settings.hotkeys.testTrigger"), action: test)
                .buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
            Spacer()
        }
        // These three are Carbon hot keys and need no Input Monitoring, so the
        // main trigger's "grant Input Monitoring" text would send users chasing
        // a permission that is irrelevant here.
        statusLine(error: manager.lastError,
                   isActive: manager.isActive,
                   combo: combo.displayString,
                   inactiveText: String(localized: "settings.hotkeys.inactive.combo"))
    }
}

// MARK: - Providers

private struct ProvidersTab: View {
    @State private var selectedProvider: String = LLMRouter.preferredProviderID
    @State private var refreshTick: Int = 0
    @State private var allowFallback: Bool = UserDefaults.standard.bool(forKey: "allowProviderFallback")
    @ObservedObject private var navigation = SettingsNavigation.shared
    /// Open provider cards. Eleven cards fully open made the pane a long
    /// scroll; at first only the default provider is open. Kept for the
    /// session — the pane stays mounted for the window's lifetime.
    @State private var expanded: Set<String> = [LLMRouter.preferredProviderID]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    defaultPickerCard
                    fallbackCard
                    ForEach(LLMRouter.allProviders.indices, id: \.self) { index in
                        let provider = LLMRouter.allProviders[index]
                        ProviderRow(provider: provider, refreshTick: refreshTick,
                                    isExpanded: isExpanded(provider.id)) {
                            refreshTick += 1
                        }
                        .id(provider.id)
                    }
                }
                .padding(20)
            }
            // "Change model…" in Autocomplete jumps here and opens MLX.
            .onReceive(navigation.$pendingProviderID.compactMap { $0 }) { id in
                expanded.insert(id)
                navigation.pendingProviderID = nil
                // Next turn: scroll to the opened card, not to its collapsed height.
                Task { @MainActor in withAnimation { proxy.scrollTo(id, anchor: .top) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private var fallbackCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $allowFallback) {
                    Text(String(localized: "settings.providers.fallback"))
                        .font(FamilyTheme.font(.headline))
                }
                .onChange(of: allowFallback) { _, new in
                    UserDefaults.standard.set(new, forKey: "allowProviderFallback")
                }
                Text(String(localized: "settings.providers.fallback.hint"))
                    .font(FamilyTheme.font(.caption))
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
                        .font(FamilyTheme.font(.headline))
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
                        expanded.insert(new)
                        // Pre-warm MLX server when user switches to it — avoids
                        // a 30–60s wait on the first transformation.
                        if new == "mlx" {
                            MLXServerManager.autoStartIfPreferred()
                        }
                    }
                }
                Text(String(localized: "settings.providers.default.hint"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }
}

private struct ProviderRow: View {
    let provider: LLMProvider
    let refreshTick: Int
    @Binding var isExpanded: Bool
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
    /// Port and custom repo ID are jargon most people never need — tucked away.
    @State private var mlxAdvancedExpanded = false

    private var isMLX: Bool { provider.id == "mlx" }

    // MARK: - MLX model presets

    struct MLXPreset: Identifiable {
        let id: String
        let label: String
        let repoID: String
        /// Actual download size, measured against the HuggingFace API, not
        /// estimated. A field rather than prose in `label` because this is the
        /// number the user needs *before* committing to a multi-GB first run —
        /// the previous list only hinted at RAM tiers ("16 GB Mac"), which
        /// several people read as the download size.
        let downloadSize: String
    }

    /// Presets curated for Tippi's use case: fast text transformation, return
    /// only the result.
    ///
    /// **Admission rule — check this before adding anything here.** By 2026
    /// almost every current small model is a thinking model, so "no reasoning
    /// models" is no longer a list one can pick from; what matters is whether
    /// the monologue can be switched *off*. `MLXProvider` sends
    /// `chat_template_kwargs: {enable_thinking: false}`, so a model qualifies
    /// only if its `chat_template.jinja` either ignores that kwarg or gates
    /// thinking on it. Read the template — the model card does not reliably say.
    /// A model that gates on something else (a `/no_think` marker in the prompt,
    /// a differently named flag) will return an empty `content` with the whole
    /// answer in `reasoning`: the exact failure v1.18.0 hit with Qwen 3.x, and
    /// it fails silently, as an empty polish rather than an error.
    ///
    /// Verified this way on 2026-09-15: Qwen 3.5 (2B/4B/9B) ✓, Gemma 4 E2B ✓
    /// (a thinking model as of Gemma 4, unlike Gemma 3, but correctly gated).
    ///
    /// Reviewed 2026-09-15: every repo ID below was verified to exist against
    /// `huggingface.co/api/models`, and the sizes were read from the same API.
    /// Note that HuggingFace answers **401, not 404**, for a repo that does not
    /// exist — so "no error" is not a check; only an explicit 200 is.
    ///
    /// These are curated for *availability, provenance and size*, which is all a
    /// catalogue can establish. They are explicitly NOT a measured quality
    /// ranking for Tippi's task, and the difference matters: the one datapoint
    /// actually measured here found a 2B model more faithful on German than a
    /// 3B one, which had distorted meaning. Recency and parameter count do not
    /// predict quality for "clean up this dictation". Ranking them honestly
    /// needs the same treatment Parakeet-vs-Whisper got — real audio, both
    /// metrics, written down.
    ///
    /// Two traps worth recording, both hit during this review:
    /// - The first pass excluded Gemma 4 after probing a *guessed* repo ID
    ///   (`gemma-4-4b-it-4bit`, which does not exist). The real builds are the
    ///   E-series (`gemma-4-e2b-it-4bit`). Probing a guess tests the guess, not
    ///   the catalogue — list the author's models instead.
    /// - Qwen3.6 and Qwen3.8 exist but only from 27B upward, so the newest Qwen
    ///   generation is irrelevant at this latency budget. "Newer family exists"
    ///   does not imply "newer family exists in the size you need".
    ///
    /// The list before that review had aged badly: six of seven entries were
    /// one to three model generations old (Llama 3.1/3.2, Qwen 2.5, Phi-4-mini,
    /// Gemma 3), and the one marked "⭐ premium" for 32 GB Macs was Qwen 2.5
    /// 14B — an ~8 GB download from late 2024, beaten by Qwen 3.5 9B at 6 GB.
    /// This is drift the v1.23.0 model-catalogue audit could not catch: that
    /// pass covered cloud providers, and none of its three defence layers
    /// (aliases, `retiredModels`, `ModelAvailabilityChecker`) apply locally —
    /// the checker is deliberately empty for Ollama/MLX. Local presets have no
    /// automatic drift protection at all, so they need a dated manual review.
    ///
    /// Deliberately NOT migrating anyone off the removed entries: unlike the
    /// cloud case, those repos still resolve (verified 200), so a saved choice
    /// keeps working. Rewriting a functioning user setting to satisfy a curated
    /// list would be the false-positive failure v1.22.1 argued against.
    ///
    /// ⭐ marks the recommended default for speed.
    static let mlxPresets: [MLXPreset] = [
        // Measured 2026-09-15 on 10 real German dictation transcripts run
        // through Tippi's own polish prompt via mlx_lm.server — same path
        // production uses, temperature 0, warm. Scored on filler removal,
        // German noun capitalisation, commas, self-correction, brand spelling
        // via the custom-word list, and whether the model answered the text
        // instead of cleaning it. Latency is the per-transcript average.
        //
        // ⭐ default. Gemma 4 E2B won on both axes at once — zero findings and
        // the fastest — which is why it displaced the 2B despite being the
        // larger download.
        MLXPreset(
            id: "gemma4-e2b",
            label: String(localized: "settings.providers.mlx.preset.gemma4-e2b"),
            repoID: "mlx-community/gemma-4-e2b-it-4bit",
            downloadSize: "3.6 GB"
        ),
        MLXPreset(
            id: "qwen35-4b-4bit",
            label: String(localized: "settings.providers.mlx.preset.qwen35-4b-4bit"),
            repoID: "mlx-community/Qwen3.5-4B-MLX-4bit",
            downloadSize: "3.1 GB"
        ),
        // Kept for 8 GB Macs and anyone who wants the smallest download, with
        // the trade-off stated rather than hidden: it left "äh"/"halt" in,
        // kept an abandoned clause, dropped sentence-final punctuation twice,
        // and ignored the custom-word list where both larger models honoured
        // it. Fine for rough notes, wrong for anything that gets sent.
        MLXPreset(
            id: "qwen35-2b-4bit",
            label: String(localized: "settings.providers.mlx.preset.qwen35-2b-4bit"),
            repoID: "mlx-community/Qwen3.5-2B-MLX-4bit",
            downloadSize: "1.7 GB"
        ),
        MLXPreset(
            id: "qwen35-9b-4bit",
            label: String(localized: "settings.providers.mlx.preset.qwen35-9b-4bit"),
            repoID: "mlx-community/Qwen3.5-9B-MLX-4bit",
            downloadSize: "6.0 GB"
        ),
    ]
    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isExpanded) {
                details.padding(.top, 8)
            } label: {
                HStack {
                    Text(provider.displayName)
                        .font(FamilyTheme.font(.headline))
                    // Visible while collapsed, so an outdated model is not hidden.
                    if availabilityChecker.staleDetails[provider.id] != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    statusBadge
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() } }
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

    /// Everything below the header. The row's @State (unsaved key, model)
    /// lives on `ProviderRow`, not in here, so collapsing loses nothing.
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hint(for: provider.id))
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.secondary)

            if let stale = availabilityChecker.staleDetails[provider.id] {
                HStack(spacing: 8) {
                    Label(String(localized: "settings.providers.modelStale"), systemImage: "exclamationmark.triangle.fill")
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.orange)
                        .help(String(localized: "settings.providers.modelStale.help"))
                    if let suggested = stale.suggested {
                        Button(String(format: String(localized: "settings.providers.modelStale.fix"), suggested)) {
                            availabilityChecker.applySuggestion(for: provider.id)
                            load()
                            onSaved()
                        }
                        .controlSize(.small)
                    }
                }
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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(mlxStatusColor)
                            .frame(width: 8, height: 8)
                        Text(mlxManager.state.displayLabel)
                            .font(FamilyTheme.font(.caption))
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

                    // First run pulls the weights from HuggingFace through
                    // mlx_lm.server. Without this row that is several GB of
                    // silence behind a "Starting…" label.
                    if let download = mlxManager.downloadStatus {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "settings.providers.mlx.downloading"))
                                    .font(FamilyTheme.font(.caption))
                                Text(download)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                    }
                } else {
                    // Not installed → friendly one-click setup card.
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .font(FamilyTheme.font(.title2))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "mlx.install.notInstalled"))
                                .font(FamilyTheme.font(.callout))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(String(localized: "mlx.install.button")) {
                            showingMLXSetup = true
                        }
                        .buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
                    }
                    .padding(8)
                    .background(.tint.opacity(0.06))
                    .cornerRadius(6)
                }
                if mlxIsInstalled || mlxPreset == "custom" {
                    MLXAdvancedSettings(isExpanded: $mlxAdvancedExpanded, modelName: $modelName, port: $mlxPort,
                                        showsCustomModel: mlxPreset == "custom", showsPort: mlxIsInstalled)
                }
            }
            // ────────────────────────────────────────────────────────────

            HStack {
                if let saveError {
                    Text(saveError)
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.red)
                } else if savedFlash {
                    Text(String(localized: "settings.providers.savedFlash"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(String(localized: "settings.providers.save"), action: save)
                    .buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
                    .disabled(saveDisabled)
            }
        }
    }

    /// Curated dropdown for hosted providers (OpenAI/Anthropic/Gemini/
    /// Mistral/OpenRouter). Falls back to a free-form text field for Ollama
    /// (whatever the user has pulled locally) and for unknown providers.
    /// The "Custom…" sentinel always lets the user type a model ID that
    /// isn't in the curated list (new releases between Tippi updates).
    @ViewBuilder
    private var curatedModelPicker: some View {
        let presets = ProviderModelPresets.presets(for: provider.id)

        if presets.isEmpty {
            HStack {
                Text(String(localized: "settings.providers.model"))
                    .font(FamilyTheme.font(.caption))
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
                        .font(FamilyTheme.font(.caption))
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
                        .font(FamilyTheme.font(.caption))
                }
            }
        }
    }

    private var mlxModelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "settings.providers.model"))
                    .font(FamilyTheme.font(.caption))
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $mlxPreset) {
                    ForEach(Self.mlxPresets) { preset in
                        // Size in the picker itself, not in a hint below it:
                        // the choice commits the user to that download, so the
                        // number belongs at the moment of choosing.
                        Text("\(preset.label) · \(preset.downloadSize)").tag(preset.id)
                    }
                    Divider()
                    Text(String(localized: "settings.providers.mlx.custom")).tag("custom")
                }
                .labelsHidden()
                .onChange(of: mlxPreset) { _, newPreset in
                    if let preset = Self.mlxPresets.first(where: { $0.id == newPreset }) {
                        modelName = preset.repoID
                    } else if newPreset == "custom" {
                        mlxAdvancedExpanded = true   // the field lives under „Erweitert"
                    }
                }
            }
            // A custom repo ID is typed under „Erweitert" (`MLXAdvancedSettings`).
            if mlxPreset != "custom" {
                Text(modelName)
                    .font(FamilyTheme.font(.caption2))
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
        .font(FamilyTheme.font(.caption))
    }

    /// An emptied field with a key on file is a removal, not "nothing to
    /// save": `setAPIKey("")` deletes the Keychain entry. Blocking it left no
    /// way to revoke a key short of Keychain Access (audit 2026-09-27).
    private var saveDisabled: Bool {
        provider.requiresAPIKey
            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasKey
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
            if let match = Self.mlxPresets.first(where: {
                $0.repoID == modelName
                    || $0.repoID == (UserDefaults.standard.string(forKey: "defaultModel.mlx") ?? MLXServerManager.defaultModel)
            }) {
                mlxPreset = match.id
                modelName = match.repoID
            } else {
                mlxPreset = "custom"
                mlxAdvancedExpanded = true
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
        // Read before the write below: `MLXServerManager.model` IS
        // `defaultModel.mlx`, so comparing afterwards always said "unchanged"
        // and a new MLX model never restarted the server (audit 2026-09-27).
        let previousMLXModel = MLXServerManager.model
        if trimmedModel.isEmpty {
            UserDefaults.standard.removeObject(forKey: "defaultModel.\(provider.id)")
        } else {
            UserDefaults.standard.set(trimmedModel, forKey: "defaultModel.\(provider.id)")
        }
        if isMLX, let p = validatedPort {
            let modelChanged = !trimmedModel.isEmpty && trimmedModel != previousMLXModel
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
        case "openrouter": return String(localized: "settings.providers.hint.openrouter")
        case "ollama":    return String(localized: "settings.providers.hint.ollama")
        case "mlx":       return String(localized: "settings.providers.hint.mlx")
        default:          return ""
        }
    }
}

/// „Erweitert" on the MLX card: the custom Hugging Face repo ID (only when
/// "Custom…" is picked — choosing it opens this) and the local server port.
/// Jargon most people never need, so it starts collapsed. Its own view to keep
/// `ProviderRow` under the type-length limit; the values stay in the row.
private struct MLXAdvancedSettings: View {
    @Binding var isExpanded: Bool
    @Binding var modelName: String
    @Binding var port: String
    let showsCustomModel: Bool
    let showsPort: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if showsCustomModel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings.providers.mlx.customRepo"))
                            .font(FamilyTheme.font(.caption))
                        TextField("mlx-community/…", text: $modelName)
                            .textFieldStyle(.roundedBorder)
                            .font(FamilyTheme.font(.caption))
                    }
                }
                if showsPort {
                    HStack {
                        Text(String(localized: "settings.providers.mlx.port"))
                            .font(FamilyTheme.font(.caption))
                        TextField("8080", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Spacer()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(String(localized: "settings.providers.advanced"))
                .font(FamilyTheme.font(.caption))
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
    }
}

// MARK: - Prompts

// PromptsTab lives in PromptsSettingsTab.swift.

// MARK: - Help

/// Groups a help entry under a category — pure data, no view logic, so the
/// 19-and-growing list of entries stays one flat, readable declaration
/// instead of view code, while `HelpTab` handles grouping/search/collapse.
private struct HelpEntry: Identifiable {
    let id: String // the title's localization key — stable, unique, no UUID churn on re-render
    let icon: String
    let category: HelpCategory
    let title: String
    let body: String
}

private enum HelpCategory: String, CaseIterable, Hashable {
    case gettingStarted, automation, snippets, providers, voice, misc, troubleshooting

    var title: String {
        switch self {
        case .gettingStarted: return String(localized: "settings.help.category.gettingStarted")
        case .automation: return String(localized: "settings.help.category.automation")
        case .snippets: return String(localized: "settings.help.category.snippets")
        case .providers: return String(localized: "settings.help.category.providers")
        case .voice: return String(localized: "settings.help.category.voice")
        case .misc: return String(localized: "settings.help.category.misc")
        case .troubleshooting: return String(localized: "settings.help.category.troubleshooting")
        }
    }
}

private struct HelpGroup: Identifiable {
    let id: HelpCategory
    let entries: [HelpEntry]
}

private struct HelpTab: View {
    @State private var searchText = ""
    @State private var manuallyExpanded: Set<HelpCategory> = Set(HelpCategory.allCases)

    // Built once per key path, not per body-render — a `static let` avoids
    // reconstructing 19 localized strings (and the `String(localized:)`
    // lookups behind them) on every keystroke while typing a search term.
    private static let allEntries: [HelpEntry] = [
        HelpEntry(id: "whatsNew", icon: "star.circle", category: .gettingStarted,
                  title: String(localized: "settings.help.whatsNewTitle"), body: String(localized: "settings.help.whatsNewBody")),
        HelpEntry(id: "how", icon: "cursorarrow.rays", category: .gettingStarted,
                  title: String(localized: "settings.help.howTitle"), body: String(localized: "settings.help.howBody")),
        HelpEntry(id: "instruct", icon: "keyboard", category: .gettingStarted,
                  title: String(localized: "settings.help.instructTitle"), body: String(localized: "settings.help.instructBody")),

        HelpEntry(id: "preview", icon: "sparkles", category: .automation,
                  title: String(localized: "settings.help.previewTitle"), body: String(localized: "settings.help.previewBody")),
        HelpEntry(id: "prompts", icon: "text.bubble", category: .automation,
                  title: String(localized: "settings.help.promptsTitle"), body: String(localized: "settings.help.promptsBody")),
        HelpEntry(id: "chains", icon: "arrow.right.circle", category: .automation,
                  title: String(localized: "settings.help.chainsTitle"), body: String(localized: "settings.help.chainsBody")),
        HelpEntry(id: "screenOCR", icon: "text.viewfinder", category: .automation,
                  title: String(localized: "settings.help.screenOCRTitle"), body: String(localized: "settings.help.screenOCRBody")),
        HelpEntry(id: "localActions", icon: "bolt", category: .automation,
                  title: String(localized: "settings.help.localActionsTitle"), body: String(localized: "settings.help.localActionsBody")),
        HelpEntry(id: "selectionPopup", icon: "rectangle.and.hand.point.up.left", category: .automation,
                  title: String(localized: "settings.help.selectionPopupTitle"), body: String(localized: "settings.help.selectionPopupBody")),
        HelpEntry(id: "variables", icon: "curlybraces", category: .automation,
                  title: String(localized: "settings.help.variablesTitle"), body: String(localized: "settings.help.variablesBody")),
        HelpEntry(id: "importExport", icon: "square.and.arrow.up.on.square", category: .automation,
                  title: String(localized: "settings.help.importExportTitle"), body: String(localized: "settings.help.importExportBody")),
        HelpEntry(id: "commandPalette", icon: "magnifyingglass", category: .automation,
                  title: String(localized: "settings.help.commandPaletteTitle"), body: String(localized: "settings.help.commandPaletteBody")),

        HelpEntry(id: "customWords", icon: "character.book.closed", category: .snippets,
                  title: String(localized: "settings.help.customWordsTitle"), body: String(localized: "settings.help.customWordsBody")),
        HelpEntry(id: "espansoImport", icon: "square.and.arrow.down", category: .snippets,
                  title: String(localized: "settings.help.espansoImportTitle"), body: String(localized: "settings.help.espansoImportBody")),
        HelpEntry(id: "snippets", icon: "text.badge.checkmark", category: .snippets,
                  title: String(localized: "settings.help.snippetsTitle"), body: String(localized: "settings.help.snippetsBody")),
        HelpEntry(id: "localModels", icon: "cpu", category: .providers,
                  title: String(localized: "settings.help.localModelsTitle"), body: String(localized: "settings.help.localModelsBody")),
        HelpEntry(id: "icloudSync", icon: "icloud", category: .misc,
                  title: String(localized: "settings.help.syncTitle"), body: String(localized: "settings.help.syncBody")),
        HelpEntry(id: "emoji", icon: "face.smiling", category: .snippets,
                  title: String(localized: "settings.help.emojiTitle"), body: String(localized: "settings.help.emojiBody")),
        HelpEntry(id: "autocomplete", icon: "text.cursor", category: .snippets,
                  title: String(localized: "settings.help.autocompleteTitle"),
                  body: String(localized: "settings.help.autocompleteBody")),

        HelpEntry(id: "api", icon: "key", category: .providers,
                  title: String(localized: "settings.help.apiTitle"), body: String(localized: "settings.help.apiBody")),
        HelpEntry(id: "pickModel", icon: "wand.and.stars.inverse", category: .providers,
                  title: String(localized: "settings.help.pickModelTitle"), body: String(localized: "settings.help.pickModelBody")),
        HelpEntry(id: "mlx", icon: "cpu", category: .providers,
                  title: String(localized: "settings.help.mlxTitle"), body: String(localized: "settings.help.mlxBody")),

        HelpEntry(id: "voice", icon: "mic", category: .voice,
                  title: String(localized: "settings.help.voiceTitle"), body: String(localized: "settings.help.voiceBody")),
        HelpEntry(id: "translate", icon: "character.bubble", category: .voice,
                  title: String(localized: "settings.help.translateTitle"), body: String(localized: "settings.help.translateBody")),

        HelpEntry(id: "appearance", icon: "circle.lefthalf.filled", category: .misc,
                  title: String(localized: "settings.help.appearanceTitle"), body: String(localized: "settings.help.appearanceBody")),
        HelpEntry(id: "notes", icon: "note.text", category: .misc,
                  title: String(localized: "settings.help.notesTitle"), body: String(localized: "settings.help.notesBody")),
        HelpEntry(id: "history", icon: "clock.arrow.circlepath", category: .misc,
                  title: String(localized: "settings.help.historyTitle"), body: String(localized: "settings.help.historyBody")),
        HelpEntry(id: "links", icon: "link", category: .misc,
                  title: String(localized: "settings.help.linksTitle"), body: String(localized: "settings.help.linksBody")),

        HelpEntry(id: "trouble", icon: "exclamationmark.triangle", category: .troubleshooting,
                  title: String(localized: "settings.help.troubleTitle"), body: String(localized: "settings.help.troubleBody")),
    ]

    private var groups: [HelpGroup] {
        let matching = searchText.isEmpty
            ? Self.allEntries
            : Self.allEntries.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        let byCategory = Dictionary(grouping: matching, by: \.category)
        return HelpCategory.allCases.compactMap { category in
            guard let entries = byCategory[category], !entries.isEmpty else { return nil }
            return HelpGroup(id: category, entries: entries)
        }
    }

    private func isExpanded(_ category: HelpCategory) -> Binding<Bool> {
        Binding(
            // While searching, every category with a match is forced open —
            // a collapsed section hiding the very result you searched for
            // would defeat the point. Clearing the search restores whatever
            // the user had manually expanded/collapsed before.
            get: { !searchText.isEmpty || manuallyExpanded.contains(category) },
            set: { expanded in
                if expanded { manuallyExpanded.insert(category) } else { manuallyExpanded.remove(category) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if groups.isEmpty {
                Spacer()
                Text(String(localized: "settings.help.noResults"))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            DisclosureGroup(isExpanded: isExpanded(group.id)) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(group.entries) { entry in
                                        helpSection(icon: entry.icon, title: entry.title, body: entry.body)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                Text(group.id.title).font(FamilyTheme.font(.title3)).fontWeight(.semibold)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "settings.help.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 8)
    }

    private func helpSection(icon: String, title: String, body: String) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .font(FamilyTheme.font(.title3))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(FamilyTheme.font(.headline))
                    // Parse the body as inline Markdown so [label](url) renders
                    // as a clickable link. Falls back to plain text on parse
                    // failure. `inlineOnlyPreservingWhitespace` keeps paragraph
                    // breaks intact (the bodies use \n\n between paragraphs).
                    Text(markdownAttributedString(from: body))
                        .font(FamilyTheme.font(.callout))
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
                    .font(FamilyTheme.font(.largeTitle))
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
                .font(FamilyTheme.font(.callout))
                .foregroundStyle(.secondary)

                Divider()

                Text(String(localized: "settings.about.copyright"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)

                Text(String(localized: "settings.about.acknowledgements"))
                    .font(FamilyTheme.font(.caption2))
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
                .font(FamilyTheme.font(.caption))
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
    /// Switched in Hotkeys → Dictation (`DictationHotkeySection`) — observed
    /// here so the options below appear and disappear with it.
    @AppStorage(DictationSettings.enabledKey) private var dictationEnabled = false
    @State private var dictationIndicatorPosition: DictationSettings.IndicatorPosition = DictationSettings.indicatorPosition
    @State private var dictationPostProcess: Bool = DictationSettings.postProcessEnabled
    @State private var dictationLayout: Bool = DictationSettings.layoutEnabled
    @State private var dictationLivePreview: Bool = DictationSettings.livePreviewEnabled
    @State private var dictationLiveTextSize: LiveTextSize = DictationSettings.liveTextSize
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
                            .font(FamilyTheme.font(.headline))
                        Text(String(localized: "settings.voice.engine.hint"))
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Picker("", selection: $engine) {
                        Text("Whisper").tag(SpeechEngine.Kind.whisper.rawValue)
                        Text("Parakeet v3").tag(SpeechEngine.Kind.parakeet.rawValue)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .onChange(of: engine) { _, new in
                        SpeechEngine.current = SpeechEngine.Kind(rawValue: new) ?? .whisper
                        parakeetStatus.refreshFromDisk()
                        // Switching to Parakeet can make dictation available
                        // without a Whisper model — re-register the hot key.
                        AppDelegate.shared?.restartDictationHotkey()
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
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.orange)
                Spacer()
                Button(String(localized: "settings.voice.engine.download")) {
                    Task { await ParakeetTranscriber.shared.prewarm() }
                }
                .controlSize(.small)
            case .downloading(let fraction):
                Text(String(localized: "settings.voice.engine.status.downloading"))
                    .font(FamilyTheme.font(.caption))
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
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
            case .ready:
                Label(String(localized: "settings.voice.engine.status.ready"),
                      systemImage: "checkmark.circle.fill")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.green)
                Spacer()
            case .failed(let message):
                Label(message, systemImage: "xmark.circle")
                    .font(FamilyTheme.font(.caption))
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

    // MARK: Dictation

    private var dictationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "settings.voice.dictation.title"))
                    .font(FamilyTheme.font(.headline))
                // On/off and the hot key itself live under Hotkeys since 2026-09-28.
                HStack(spacing: 8) {
                    Text(String(localized: "settings.voice.dictation.hotkeyMoved"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(String(localized: "settings.voice.dictation.openHotkeys")) {
                        SettingsNavigation.shared.pendingTab = .hotkeys
                    }
                    .controlSize(.small)
                }

                if dictationEnabled {
                    Picker(String(localized: "settings.voice.dictation.indicator.position"),
                           selection: $dictationIndicatorPosition) {
                        Text(String(localized: "settings.voice.dictation.indicator.topLeft")).tag(DictationSettings.IndicatorPosition.topLeft)
                        Text(String(localized: "settings.voice.dictation.indicator.top")).tag(DictationSettings.IndicatorPosition.top)
                        Text(String(localized: "settings.voice.dictation.indicator.topRight")).tag(DictationSettings.IndicatorPosition.topRight)
                        Divider()
                        Text(String(localized: "settings.voice.dictation.indicator.bottomLeft")).tag(DictationSettings.IndicatorPosition.bottomLeft)
                        Text(String(localized: "settings.voice.dictation.indicator.bottom")).tag(DictationSettings.IndicatorPosition.bottom)
                        Text(String(localized: "settings.voice.dictation.indicator.bottomRight")).tag(DictationSettings.IndicatorPosition.bottomRight)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: dictationIndicatorPosition) { _, new in
                        DictationSettings.indicatorPosition = new
                    }

                    Toggle(String(localized: "settings.voice.dictation.livePreview.enable"), isOn: $dictationLivePreview)
                        .onChange(of: dictationLivePreview) { _, new in DictationSettings.livePreviewEnabled = new }
                        .disabled(engine != SpeechEngine.Kind.parakeet.rawValue)
                    Text(String(localized: engine == SpeechEngine.Kind.parakeet.rawValue
                                ? "settings.voice.dictation.livePreview.body"
                                : "settings.voice.dictation.livePreview.parakeetOnly"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if dictationLivePreview && engine == SpeechEngine.Kind.parakeet.rawValue {
                        Picker(String(localized: "settings.voice.dictation.livePreview.size"), selection: $dictationLiveTextSize) {
                            Text(String(localized: "settings.voice.dictation.livePreview.size.normal")).tag(LiveTextSize.normal)
                            Text(String(localized: "settings.voice.dictation.livePreview.size.large")).tag(LiveTextSize.large)
                            Text(String(localized: "settings.voice.dictation.livePreview.size.extraLarge")).tag(LiveTextSize.extraLarge)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: dictationLiveTextSize) { _, new in DictationSettings.liveTextSize = new }
                    }

                    Divider().padding(.vertical, 4)

                    DictationAutoReturnSection()

                    Divider().padding(.vertical, 4)

                    Toggle(String(localized: "settings.voice.dictation.postProcess.enable"),
                           isOn: $dictationPostProcess)
                        .onChange(of: dictationPostProcess) { _, new in
                            DictationSettings.postProcessEnabled = new
                        }

                    Text(String(localized: "settings.voice.dictation.postProcess.body"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Outside the polish block: the closing rule works without AI.
                    Toggle(String(localized: "settings.voice.dictation.layout.enable"), isOn: $dictationLayout)
                        .onChange(of: dictationLayout) { _, new in DictationSettings.layoutEnabled = new }
                    Text(String(localized: "settings.voice.dictation.layout.body"))
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if dictationPostProcess {
                        polishProviderPicker

                        Text(String(localized: "settings.voice.dictation.postProcess.promptLabel"))
                            .font(FamilyTheme.font(.caption))
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
    /// "use the same provider as everything else"; a fast hosted model
    /// (e.g. Mistral Small, Gemini Flash Lite) keeps polish latency short.
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
                    .font(FamilyTheme.font(.caption))
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
                        .font(FamilyTheme.font(.caption))
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
                    .font(FamilyTheme.font(.headline))
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
                    .font(FamilyTheme.font(.headline))
                Toggle(String(localized: "settings.voice.systemAudio.enable"), isOn: $muteSystemAudio)
                    .onChange(of: muteSystemAudio) { _, new in
                        AudioRecorder.muteSystemAudioDuringRecording = new
                    }
                Text(String(localized: "settings.voice.systemAudio.body"))
                    .font(FamilyTheme.font(.caption))
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
                        .font(FamilyTheme.font(.headline))
                    Spacer()
                    // Overall status pill
                    if WhisperConfig.autoDetectedModelPath != nil {
                        Label(String(localized: "setup.granted"), systemImage: "checkmark.circle.fill")
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.green)
                    } else {
                        Label(String(localized: "voice.model.noModel"), systemImage: "exclamationmark.circle")
                            .font(FamilyTheme.font(.caption))
                            .foregroundStyle(.orange)
                    }
                }

                Divider()

                ForEach(WhisperModel.catalog) { model in
                    ModelRow(model: model, manager: modelManager)
                }

                // Written by the download on every failure but never shown —
                // the row just flipped back to "Download" (audit 2026-09-27).
                if let error = modelManager.downloadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(FamilyTheme.font(.headline))
                    Text(String(localized: "settings.voice.language.hint"))
                        .font(FamilyTheme.font(.caption))
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
                .onChange(of: language) { _, new in
                    WhisperConfig.language = new
                    // The menu-bar submenu showed the old checkmark (audit 2026-09-27).
                    AppDelegate.shared?.rebuildDictationLanguageMenu()
                }
            }
            .padding(6)
        }
    }

    // MARK: Advanced (power users)

    private var advancedSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.voice.advanced.title"))
                    .font(FamilyTheme.font(.headline))
                Text(String(localized: "settings.voice.advanced.body"))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    let status = WhisperConfig.autoDetectedBinaryPath
                    Image(systemName: status != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(status != nil ? Color.green : Color.orange)
                        .font(FamilyTheme.font(.caption))
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
                    .font(FamilyTheme.font(.subheadline))
                HStack(spacing: 6) {
                    Text("\(model.sizeMB) MB")
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(FamilyTheme.font(.caption))
                        .foregroundStyle(.secondary)
                    Text(model.languages)
                        .font(FamilyTheme.font(.caption))
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
                    .font(FamilyTheme.font(.caption2))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } else if isDownloaded {
                Button(String(localized: "voice.model.delete")) {
                    manager.delete(model)
                    isDownloaded = false
                }
                .buttonStyle(.bordered)
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(.red)
            } else {
                Button(String(localized: "voice.model.download")) {
                    manager.download(model)
                }
                .buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
                .font(FamilyTheme.font(.caption))
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
