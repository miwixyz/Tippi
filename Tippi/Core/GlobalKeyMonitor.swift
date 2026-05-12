import AppKit

/// Listens for a configurable global key combo via `NSEvent.addGlobalMonitorForEvents`.
/// Requires only Accessibility permission (no Input Monitoring), which is the same
/// permission Tippi already needs to read selected text.
@MainActor
final class GlobalKeyMonitor: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastTriggerAt: Date?
    @Published private(set) var lastError: String?

    private(set) var combo: KeyCombo
    private var onTrigger: (@MainActor () -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(combo: KeyCombo = .default) {
        self.combo = combo
    }

    func start(onTrigger: @escaping @MainActor () -> Void) {
        guard !isActive else { return }
        self.onTrigger = onTrigger
        self.lastError = nil

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }

        // Local monitor catches events when Tippi itself is the focused app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }

        if globalMonitor == nil {
            lastError = "Couldn't register global key monitor. Grant Accessibility permission and try again."
            NSLog("Tippi: GlobalKeyMonitor — addGlobalMonitorForEvents returned nil")
        } else {
            isActive = true
            NSLog("Tippi: GlobalKeyMonitor active for \(combo.displayString)")
        }
    }

    func stop() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
        isActive = false
    }

    func update(combo: KeyCombo) {
        self.combo = combo
        let restart = isActive
        let handler = onTrigger
        if restart { stop() }
        if restart, let handler { start(onTrigger: handler) }
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    private func handle(_ event: NSEvent) {
        let eventMods = event.modifierFlags.intersection(Self.relevantModifiers)
        let comboMods = combo.modifiers.intersection(Self.relevantModifiers)
        guard eventMods == comboMods, event.keyCode == combo.keyCode else { return }
        lastTriggerAt = Date()
        NSLog("Tippi: GlobalKeyMonitor caught \(combo.displayString) (mods=\(eventMods.rawValue), keyCode=\(event.keyCode))")
        onTrigger?()
    }
}
