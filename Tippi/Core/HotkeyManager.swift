import AppKit
import Carbon
import CoreGraphics

@MainActor
final class HotkeyManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastTriggerAt: Date?
    @Published private(set) var lastError: String?

    private(set) var currentTrigger: HotkeyTrigger
    private var onTrigger: (@MainActor () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var lastReleaseTimestamp: CFTimeInterval = 0
    private var holdTimer: Timer?

    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?

    init(trigger: HotkeyTrigger = .default) {
        self.currentTrigger = trigger
    }

    func start(onTrigger: @escaping @MainActor () -> Void) {
        guard !isActive else { return }
        self.onTrigger = onTrigger
        lastError = nil

        switch currentTrigger {
        case .doubleTap, .hold:
            startEventTap()
        case .combo(let keyCode, let flags):
            registerCarbonHotKey(keyCode: keyCode, modifierFlags: flags)
        }
    }

    func stop() {
        stopEventTap()
        unregisterCarbonHotKey()
        holdTimer?.invalidate()
        holdTimer = nil
        isActive = false
    }

    func update(trigger: HotkeyTrigger) {
        let wasActive = isActive
        let handler = onTrigger
        if wasActive { stop() }
        self.currentTrigger = trigger
        if wasActive, let handler { start(onTrigger: handler) }
    }

    fileprivate func fireTrigger() {
        lastTriggerAt = Date()
        onTrigger?()
    }

    // MARK: - CGEventTap (Double-Tap + Hold)

    private func startEventTap() {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: HotkeyManager.eventTapCallback,
            userInfo: selfPtr
        ) else {
            lastError = "CGEvent.tapCreate failed — grant Input Monitoring permission and restart Tippi."
            NSLog("Tippi: \(lastError ?? "")")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isActive = true
    }

    private func stopEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

        // Handle re-enable inline (it's safe from this thread)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in manager.reenableTap() }
            return Unmanaged.passUnretained(event)
        }

        // Copy primitive values before hopping to MainActor (event is mutable, lifetime is callback-scope)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        Task { @MainActor in
            manager.handleFlagsChanged(keyCode: keyCode, flags: flags)
        }
        return Unmanaged.passUnretained(event)
    }

    private func reenableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: CGEventFlags) {
        switch currentTrigger {
        case .doubleTap(let modifier, let thresholdMs):
            guard keyCode == modifier.keyCode else { return }
            let pressed = isModifierPressed(group: modifier, flags: flags)
            if !pressed {
                let now = CFAbsoluteTimeGetCurrent()
                let elapsedMs = (now - lastReleaseTimestamp) * 1000
                if elapsedMs < Double(thresholdMs) {
                    fireTrigger()
                    lastReleaseTimestamp = 0
                } else {
                    lastReleaseTimestamp = now
                }
            }

        case .hold(let modifier, let durationMs):
            guard keyCode == modifier.keyCode else { return }
            let pressed = isModifierPressed(group: modifier, flags: flags)
            if pressed {
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(
                    withTimeInterval: Double(durationMs) / 1000.0,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in self?.fireTrigger() }
                }
            } else {
                holdTimer?.invalidate()
                holdTimer = nil
            }

        case .combo:
            return // handled by Carbon
        }
    }

    private func isModifierPressed(group: ModifierKey, flags: CGEventFlags) -> Bool {
        switch group {
        case .leftShift, .rightShift:     return flags.contains(.maskShift)
        case .leftControl, .rightControl: return flags.contains(.maskControl)
        case .leftOption, .rightOption:   return flags.contains(.maskAlternate)
        case .leftCommand, .rightCommand: return flags.contains(.maskCommand)
        }
    }

    // MARK: - Carbon (Normal Combo)

    private func registerCarbonHotKey(keyCode: UInt32, modifierFlags: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54505049), id: 1) // 'TPPI'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, ref != nil else {
            lastError = "RegisterEventHotKey failed (\(status))"
            NSLog("Tippi: \(lastError ?? "")")
            return
        }
        self.carbonHotKeyRef = ref
        installCarbonHandler()
        self.isActive = true
    }

    private func unregisterCarbonHotKey() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        if let handler = carbonEventHandler {
            RemoveEventHandler(handler)
            carbonEventHandler = nil
        }
    }

    private func installCarbonHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            1,
            &eventSpec,
            selfPtr,
            &carbonEventHandler
        )
        if status != noErr {
            NSLog("Tippi: InstallEventHandler failed (\(status))")
        }
    }
}

// Stateless C-compatible callback for Carbon
private func carbonHotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in manager.fireTrigger() }
    return noErr
}
