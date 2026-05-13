import AppKit
import Carbon
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissions = PermissionsManager()
    let hotkeyManager = HotkeyManager()
    let keyMonitor = GlobalKeyMonitor(combo: KeyComboStore.load())
    let audioRecorder = AudioRecorder()

    private var statusItem: NSStatusItem?
    private var welcomeWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var lastNonTippiApp: NSRunningApplication?
    private let popupController = PromptPopupController()
    private let previewWindowController = PreviewWindowController()
    private var cancellables = Set<AnyCancellable>()
    private var updaterController: SPUStandardUpdaterController?

    private var safetyHotKeyRef: EventHotKeyRef?
    private var safetyHotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Tippi: applicationDidFinishLaunching")
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        setupMenuBar()
        observeFrontmostApp()
        observePermissions()
        hotkeyManager.update(trigger: loadHotkeyTrigger())
        registerSafetyHotKey()
        startGlobalKeyMonitor()
        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            showWelcomeWindow()
        }
        startHotkey()
    }

    private func startGlobalKeyMonitor() {
        keyMonitor.start { [weak self] in
            Task { @MainActor in
                NSLog("Tippi: GlobalKeyMonitor → triggerManually")
                self?.triggerManually()
            }
        }
    }

    /// Always-on Carbon hotkey ⌃⌥⌘T. Carbon does not need Input Monitoring permission,
    /// so this works even when the user-configured tap (⌥⌥) cannot be created.
    private func registerSafetyHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54505059), id: 99) // 'TPPY'
        var ref: EventHotKeyRef?
        let modifiers: UInt32 = UInt32(cmdKey | optionKey | controlKey)
        let keyCode: UInt32 = 17 // kVK_ANSI_T

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, ref != nil else {
            NSLog("Tippi: safety hotkey registration failed (status=\(status))")
            return
        }
        safetyHotKeyRef = ref

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            safetyHotKeyCallback,
            1,
            &eventSpec,
            selfPtr,
            &safetyHotKeyHandler
        )
        if installStatus != noErr {
            NSLog("Tippi: safety hotkey handler install failed (status=\(installStatus))")
        } else {
            NSLog("Tippi: safety hotkey ⌃⌥⌘T registered")
        }
    }

    private func loadHotkeyTrigger() -> HotkeyTrigger {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "hotkeyMode") ?? "doubleTap"
        let modString = defaults.string(forKey: "hotkeyModifier") ?? ModifierKey.rightOption.rawValue
        guard let mod = ModifierKey(rawValue: modString) else { return .default }
        switch mode {
        case "hold":
            let raw = defaults.integer(forKey: "hotkeyHoldMs")
            return .hold(modifier: mod, durationMs: raw > 0 ? raw : 500)
        case "doubleTap":
            let raw = defaults.integer(forKey: "hotkeyDoubleTapMs")
            return .doubleTap(modifier: mod, thresholdMs: raw > 0 ? raw : 300)
        default:
            return .default
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "pencil.and.outline",
            accessibilityDescription: "Tippi"
        )

        let menu = NSMenu()
        let triggerItem = NSMenuItem(
            title: String(localized: "menu.trigger"),
            action: #selector(triggerManually),
            keyEquivalent: "t"
        )
        triggerItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(triggerItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: String(localized: "menu.checkForUpdates"),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "menu.welcome"),
            action: #selector(showWelcomeWindow),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "menu.settings"),
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        for entry in menu.items where entry.action != #selector(NSApplication.terminate(_:)) {
            entry.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    @objc func showWelcomeWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if welcomeWindowController == nil {
            let hostingController = NSHostingController(
                rootView: WelcomeView()
                    .environmentObject(permissions)
                    .environmentObject(hotkeyManager)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Tippi"
            window.setContentSize(NSSize(width: 600, height: 480))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindowController = NSWindowController(window: window)
        }

        welcomeWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindowController == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(permissions)
                    .environmentObject(hotkeyManager)
                    .environmentObject(keyMonitor)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "settings.window.title")
            window.setContentSize(NSSize(width: 640, height: 580))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Frontmost-app tracking

    private func observeFrontmostApp() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceDidActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceDidActivateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastNonTippiApp = app
        }
    }

    // MARK: - Permissions observation (auto-restart hotkey + key monitor)

    private func observePermissions() {
        // Input Monitoring → restart event tap
        permissions.$inputMonitoringGranted
            .removeDuplicates()
            .sink { [weak self] granted in
                guard let self else { return }
                if granted && !self.hotkeyManager.isActive {
                    NSLog("Tippi: Input Monitoring granted — (re)starting hotkey")
                    self.startHotkey()
                }
            }
            .store(in: &cancellables)

        // Accessibility → restart global key monitor.
        // Fires at startup (TCC loads after the monitor tried to register)
        // and whenever the user re-grants the permission in System Settings.
        permissions.$accessibilityGranted
            .removeDuplicates()
            .sink { [weak self] granted in
                guard let self else { return }
                if granted && !self.keyMonitor.isActive {
                    NSLog("Tippi: Accessibility granted — (re)starting key monitor")
                    self.startGlobalKeyMonitor()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey wiring

    private func startHotkey() {
        hotkeyManager.start { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleTriggered(from: .hotkey)
            }
        }
    }

    /// Manual trigger from menubar.
    /// Works without Input Monitoring, but still needs Accessibility to read selected text.
    @objc func triggerManually() {
        Task { @MainActor in
            await handleTriggered(from: .manual)
        }
    }

    /// Permission-free demo entry used by the Welcome wizard's "Try Tippi" button.
    /// Shows the popup with a built-in demo text and a result alert — no capture or paste.
    @objc func runDemoPopup() {
        guard !popupController.isOpen else { return }
        let demoText = String(localized: "setup.tryIt.demo.text")
        NSLog("Tippi: runDemoPopup launched")

        let mouseLocation = NSEvent.mouseLocation
        let prompts = DemoPrompt.all
        popupController.show(
            at: mouseLocation,
            prompts: prompts,
            onSelect: { [weak self] prompt in
                Task { @MainActor in
                    self?.showDemoResult(prompt: prompt, original: demoText)
                }
            },
            onDismiss: {
                NSLog("Tippi: demo popup dismissed")
            }
        )
    }

    private func showDemoResult(prompt: DemoPrompt, original: String) {
        let transformed = prompt.transform(original)
        NSLog("Tippi: demo result for \(prompt.id)")

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(
            format: String(localized: "demo.result.title"),
            prompt.title
        )
        alert.informativeText = """
        \(String(localized: "demo.result.original")):
        \(original)

        \(String(localized: "demo.result.transformed")):
        \(transformed)
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    private enum TriggerSource { case hotkey, manual }

    private func handleTriggered(from source: TriggerSource) async {
        NSLog("Tippi: handleTriggered from=\(source)")
        guard !popupController.isOpen && !previewWindowController.isOpen else {
            NSLog("Tippi: popup or preview already open — ignoring")
            return
        }

        // For hotkey: brief pause so the trigger modifier finishes releasing.
        if source == .hotkey {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        let sourceApp = lastNonTippiApp
        NSLog("Tippi: source app = \(sourceApp?.localizedName ?? "nil")")
        let captured = await TextCapture.captureSelectedText(sourceApp: sourceApp)
        let mouseLocation = NSEvent.mouseLocation
        let prompts = DemoPrompt.all

        if let captured {
            NSLog("Tippi: captured \(captured.text.count) chars from \(captured.sourceApp?.localizedName ?? "?")")
        } else {
            NSLog("Tippi: no text captured — showing popup with voice option")
        }

        // Resolve mic permission before showing popup.
        let micReady: Bool
        if WhisperConfig.isConfigured {
            micReady = await AudioRecorder.requestPermission()
        } else {
            micReady = false
        }

        popupController.show(
            at: mouseLocation,
            prompts: prompts,
            onSelect: { [weak self] prompt in
                guard let self, let captured else { return }
                self.showPreview(prompt: prompt, captured: captured)
            },
            onDismiss: { /* nothing — user cancelled */ },
            audioRecorder: micReady ? audioRecorder : nil,
            // When text is selected, mic = voice instruction; otherwise = dictation
            voiceMode: captured != nil ? .voicePrompt : .dictate,
            onVoiceTranscribed: { [weak self] transcribedText in
                guard let self else { return }
                if let captured {
                    // Voice prompt mode: transcript is the AI instruction for selected text
                    let voicePrompt = DemoPrompt(
                        id: "voice-prompt",
                        title: String(localized: "voice.promptTitle"),
                        symbol: "mic",
                        systemPrompt: transcribedText
                            + " Return only the result without any commentary, explanation, or quotes.",
                        transform: { @Sendable in $0 }
                    )
                    self.showPreview(prompt: voicePrompt, captured: captured)
                } else {
                    // Dictate mode: show popup with the transcript so user can
                    // pick an AI prompt or use "Direkt einfügen".
                    let voiceCaptured = CapturedText(
                        text: transcribedText,
                        sourceApp: sourceApp,
                        usedClipboardFallback: false
                    )
                    self.showPopupWithText(voiceCaptured, at: mouseLocation, prompts: prompts)
                }
            }
        )

        // If no text AND voice not available → show the original alert as fallback.
        if captured == nil && !micReady && !WhisperConfig.isConfigured {
            popupController.close()
            await showNoTextAlert()
        }
    }

    /// Re-shows the popup pre-loaded with dictated text.
    /// Offers "Direkt einfügen" at the top (default) plus all AI prompts.
    private func showPopupWithText(
        _ captured: CapturedText,
        at mouseLocation: NSPoint,
        prompts: [DemoPrompt]
    ) {
        popupController.show(
            at: mouseLocation,
            prompts: prompts,
            onSelect: { [weak self] prompt in
                self?.showPreview(prompt: prompt, captured: captured)
            },
            onDismiss: { },
            onDirectInsert: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.pasteBack(captured.text, into: captured.sourceApp)
                }
            }
        )
    }

    private func showPreview(prompt: DemoPrompt, captured: CapturedText) {
        previewWindowController.show(
            prompt: prompt,
            originalText: captured.text,
            sourceApp: captured.sourceApp,
            onReplace: { [weak self] suggestion in
                Task { @MainActor in
                    await self?.pasteBack(suggestion, into: captured.sourceApp)
                }
            },
            onAppend: { [weak self] suggestion in
                let combined = "\(captured.text) \(suggestion)"
                Task { @MainActor in
                    await self?.pasteBack(combined, into: captured.sourceApp)
                }
            },
            onCopy: { suggestion in
                TextInsertion.copy(suggestion)
            },
            onCancel: { /* nothing */ }
        )
    }

    private func pasteBack(_ text: String, into app: NSRunningApplication?) async {
        app?.activate()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await TextInsertion.replace(with: text)
    }

    private func showNoTextAlert() async {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.noText.title")
        alert.informativeText = String(localized: "alert.noText.body")
        alert.alertStyle = .informational
        alert.runModal()
    }
}

/// Stateless C-compatible callback for the Carbon safety hotkey.
private func safetyHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        NSLog("Tippi: safety hotkey fired")
        delegate.triggerManually()
    }
    return noErr
}
