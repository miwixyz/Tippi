import AppKit
import ApplicationServices
import Carbon
import os

private let autocompleteLog = Logger(subsystem: "com.tippi.app", category: "autocomplete")

/// Labs: Autovervollständigung beim Tippen — Verdrahtung mit dem System.
///
/// Ablauf (docs/SECURE-DESIGN-autocomplete.md): Tastendruck → 350 ms Pause →
/// Kontext per Bedienungshilfen lesen (Ausschlussprüfung zuerst) → eine Anfrage an
/// Tippis **eigenen** MLX-Server → Antwort bereinigen → grauer Vorschlag am
/// Cursor → ⇥ übernimmt über `TextInsertion`, alles andere verwirft.
///
/// Die Entscheidungen selbst (was gelesen, geschluckt, angezeigt wird) stehen
/// rein und getestet in `AutocompleteLogic.swift`; hier wird nur verdrahtet.
///
/// Protokolliert werden nur Bundle-ID, Längen und Dauer — **nie Textinhalt**.
@MainActor
final class AutocompleteController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    /// Design §3: Anfrage erst nach 350 ms Pause.
    static let pauseNanoseconds: UInt64 = 350_000_000

    /// Wahr, solange Emoji-Vorschlag, Auswahlleiste oder Snippet-Erweiterung
    /// gerade aktiv sind — dann kein Vorschlag, damit sich nichts überlagert.
    private let isOtherTypingUIActive: () -> Bool

    private let bridge = AutocompleteTapBridge()
    private let panel = AutocompleteSuggestionPanel()
    private var runLoopSource: CFRunLoopSource?
    private var appSwitchObserver: NSObjectProtocol?
    private var pauseTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    /// Wird bei jedem Tastendruck erhöht; eine Antwort mit veralteter Nummer
    /// wird verworfen (höchstens eine gültige Anfrage, Design §3).
    private var generation = 0
    private var shown: (text: String, pid: pid_t)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = AutocompleteRequest.timeout
        config.timeoutIntervalForResource = AutocompleteRequest.timeout
        config.urlCache = nil
        config.httpCookieStorage = nil
        // Kein System-Proxy: die Anfrage darf den Rechner nicht verlassen.
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config, delegate: RefuseRedirects(), delegateQueue: nil)
    }()

    init(isOtherTypingUIActive: @escaping () -> Bool) {
        self.isOtherTypingUIActive = isOtherTypingUIActive
        bridge.controller = self
    }

    // MARK: - An / Aus

    /// Liest die Einstellung und startet bzw. entfernt den Tap. Aus = Tap sofort
    /// weg, keine Anfragen mehr (Design §4 „Abschalten im Ernstfall").
    func apply() {
        isEnabled = AutocompleteSettings.isEnabled
        if isEnabled { start() } else { stop() }
    }

    private func start() {
        guard bridge.tap == nil else { return }
        lastError = nil
        guard AXIsProcessTrusted() else {
            lastError = String(localized: "autocomplete.error.accessibility")
            return
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        // `.defaultTap` (aktiv) statt `.listenOnly`: nur so kann ⇥ geschluckt
        // werden. Existiert ausschließlich, solange die Funktion an ist.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: autocompleteTapCallback,
            userInfo: Unmanaged.passUnretained(bridge).toOpaque()
        ) else {
            lastError = String(localized: "autocomplete.error.tap")
            autocompleteLog.error("tapCreate failed")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        bridge.tap = tap
        runLoopSource = source

        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelPending()
                self?.dismiss()
            }
        }

        // Nutzt nur den selbst gestarteten Server. Wer die Funktion einschaltet,
        // will Vorschläge — ohne diesen Start gäbe es nach jedem Neustart von
        // Tippi keine, solange MLX nicht der Standard-Anbieter ist.
        if MLXServerManager.isInstalled, MLXServerManager.shared.state == .stopped {
            Task { try? await MLXServerManager.shared.start() }
        }
        autocompleteLog.notice("autocomplete on")
    }

    private func stop() {
        cancelPending()
        dismiss()
        if let tap = bridge.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        bridge.tap = nil
        runLoopSource = nil
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        appSwitchObserver = nil
        autocompleteLog.notice("autocomplete off")
    }

    // MARK: - Ereignisse aus dem Tap

    func userTyped(restartPause: Bool) {
        cancelPending()
        dismiss()
        guard restartPause else { return }
        pauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.pauseNanoseconds)
            guard !Task.isCancelled else { return }
            autocompleteLog.notice("pause elapsed")
            self?.requestSuggestion()
        }
    }

    func userClicked() {
        cancelPending()
        dismiss()
    }

    /// ⇥ wurde bereits geschluckt. Kann der Vorschlag nicht mehr eingefügt
    /// werden, wird das ⇥ nachgereicht — es darf nie verloren gehen (Design §3).
    func acceptShownSuggestion() {
        let front = NSWorkspace.shared.frontmostApplication
        // Passwort-Eingabe erneut prüfen: Der Fokus kann seit dem Anzeigen ohne
        // Taste/Klick gewechselt sein (Seite springt selbst ins Passwortfeld).
        guard let shown, front?.processIdentifier == shown.pid, !IsSecureEventInputEnabled() else {
            dismiss()
            Self.repostTab()
            return
        }
        let text = shown.text
        cancelPending()
        dismiss()
        autocompleteLog.notice("accepted bundle=\(front?.bundleIdentifier ?? "?", privacy: .public) len=\(text.count, privacy: .public)")
        Task { await TextInsertion.replace(with: text, in: front) }
    }

    private func cancelPending() {
        generation &+= 1
        pauseTask?.cancel()
        requestTask?.cancel()
        pauseTask = nil
        requestTask = nil
    }

    private func dismiss() {
        bridge.setVisible(false)
        panel.close()
        shown = nil
    }

    // MARK: - Vorschlag holen

    private func requestSuggestion() {
        // Messpunkte (2026-09-25, „es kommt gar nichts"): jeder Ausstieg nennt
        // seinen Grund — nur Gründe und Zahlen, nie getippten Text.
        guard bridge.tap != nil else { return skip("no tap") }
        guard !isOtherTypingUIActive() else { return skip("other typing UI active") }
        guard let server = MLXServerManager.shared.ownedServerURL else {
            return skip("no server started by Tippi (state=\(MLXServerManager.shared.state))")
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return skip("no frontmost app") }
        guard let field = readFocusedField(in: app) else { return }
        guard let request = AutocompleteRequest.make(server: server, model: MLXServerManager.activeModel,
                                                     context: field.context) else { return skip("request not built") }
        let gen = generation
        let started = Date()
        let bundleID = app.bundleIdentifier ?? "?"
        requestTask = Task { [weak self] in
            guard let self else { return }
            let raw = await self.fetch(request)
            guard !Task.isCancelled, gen == self.generation else { return }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            guard let raw,
                  let suggestion = AutocompleteSanitizer.clean(raw, context: field.context, isKnownWord: Self.isKnownWord),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  !self.isOtherTypingUIActive() else {
                autocompleteLog.notice("no suggestion bundle=\(bundleID, privacy: .public) ctx=\(field.context.utf16.count, privacy: .public) ms=\(ms, privacy: .public)")
                return
            }
            self.panel.show(suggestion, caret: field.caret)
            self.shown = (suggestion, app.processIdentifier)
            self.bridge.setVisible(true)
            autocompleteLog.notice("shown bundle=\(bundleID, privacy: .public) ctx=\(field.context.utf16.count, privacy: .public) len=\(suggestion.count, privacy: .public) ms=\(ms, privacy: .public)")
        }
    }

    private func skip(_ why: String) {
        autocompleteLog.notice("skip: \(why, privacy: .public)")
    }

    private func fetch(_ request: URLRequest) async -> String? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return AutocompleteRequest.content(from: data)
    }

    private static func isKnownWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }

    private static func repostTab() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(AutocompleteKeyDecision.tabKeyCode),
                                keyDown: keyDown)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Fokussiertes Feld lesen

    private struct Field {
        let context: String
        let caret: CGRect
    }

    /// Kontext vor dem Cursor und Cursor-Position — oder `nil`, wenn nicht
    /// gelesen werden darf oder kann. Die Ausschlussprüfung läuft, bevor ein
    /// einziges Zeichen Text gelesen wird.
    private func readFocusedField(in app: NSRunningApplication) -> Field? {
        guard AXIsProcessTrusted() else { skip("not trusted (Bedienungshilfen)"); return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Eine hängende App darf das Tippen nicht einfrieren.
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let focused = Self.element(appElement, kAXFocusedUIElementAttribute)
        if let reason = AutocompleteExclusion.reason(
            bundleID: app.bundleIdentifier,
            role: focused.flatMap { Self.string($0, kAXRoleAttribute) },
            subrole: focused.flatMap { Self.string($0, kAXSubroleAttribute) },
            secureInputActive: IsSecureEventInputEnabled(),
            excludedBundleIDs: Set(AutocompleteSettings.excludedBundleIDs),
            ownBundleID: Bundle.main.bundleIdentifier,
            isEditable: focused.map(Self.isValueSettable) ?? false
        ) {
            skip("\(reason.rawValue) bundle=\(app.bundleIdentifier ?? "?") role=\(focused.flatMap { Self.string($0, kAXRoleAttribute) } ?? "?")")
            return nil
        }
        guard let focused else { skip("no focused element"); return nil }
        // Web-Inhalt (Mail) kennt keine AXSelectedTextRange, nur WebKit-Textmarker.
        // Die Cursorstelle wird darüber in eine Zahl umgerechnet; Text und
        // Position laufen danach über dieselben Aufrufe wie überall (gemessen
        // 2026-09-25 an einem bearbeitbaren WebKit-Dokument).
        guard let range = Self.selectedRange(focused) ?? Self.selectedRangeViaTextMarkers(focused) else {
            skip("no selected range role=\(Self.string(focused, kAXRoleAttribute) ?? "?")"); return nil
        }
        guard range.length == 0, range.location > 0 else {   // Auswahl aktiv → nichts
            skip("selection len=\(range.length) loc=\(range.location)"); return nil
        }
        AXUIElementSetMessagingTimeout(focused, 0.25)
        let loc = range.location
        let start = max(0, loc - AutocompleteContext.maxUTF16)

        let context: String
        let next: Character?
        if let tail = Self.string(focused, forRange: CFRange(location: start, length: loc - start)) {
            context = AutocompleteContext.beforeCursor(in: tail, cursorUTF16: tail.utf16.count)
            next = Self.string(focused, forRange: CFRange(location: loc, length: 1))?.first
        } else if let full = Self.string(focused, kAXValueAttribute) {
            context = AutocompleteContext.beforeCursor(in: full, cursorUTF16: loc)
            let cursor = full.utf16.index(full.utf16.startIndex, offsetBy: min(loc, full.utf16.count))
            next = full.unicodeScalars[cursor...].first.map(Character.init)
        } else {
            skip("text not readable role=\(Self.string(focused, kAXRoleAttribute) ?? "?")")
            return nil
        }
        guard AutocompleteContext.isLongEnough(context) else { skip("context too short"); return nil }
        guard AutocompleteContext.cursorIsAtLineEnd(nextCharacter: next) else { skip("not at line end"); return nil }
        guard let caret = caretRect(focused, location: loc) else { skip("no plausible caret bundle=\(app.bundleIdentifier ?? "?")"); return nil }
        return Field(context: context, caret: caret)
    }

    /// Cursor-Rechteck (Breite 0) oder `nil`, wenn die App keine plausiblen
    /// Bounds liefert — dann lieber kein Vorschlag als ein falsch platzierter.
    private func caretRect(_ element: AXUIElement, location: Int) -> CGRect? {
        let screens = NSScreen.screens.map(\.frame)
        if let rect = TextCapture.boundsForSelection(element: element, range: CFRange(location: location, length: 0)),
           AutocompleteGeometry.isPlausibleCaret(rect, screens: screens) {
            return CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
        }
        if let rect = TextCapture.boundsForSelection(element: element, range: CFRange(location: location - 1, length: 1)),
           AutocompleteGeometry.isPlausibleCaret(rect, screens: screens) {
            return CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
        }
        return nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        return (raw as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func string(_ element: AXUIElement, forRange range: CFRange) -> String? {
        var mutable = range
        guard range.length > 0, let axRange = AXValueCreate(.cfRange, &mutable) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &ref
        ) == .success else { return nil }
        return ref as? String
    }

    private static func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private static func selectedRangeViaTextMarkers(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        let markers = raw as! AXTextMarkerRange
        guard let start = index(of: AXTextMarkerRangeCopyStartMarker(markers), in: element),
              let end = index(of: AXTextMarkerRangeCopyEndMarker(markers), in: element),
              start >= 0, end >= start else { return nil }
        return CFRange(location: start, length: end - start)
    }

    private static func index(of marker: AXTextMarker, in element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXIndexForTextMarker" as CFString, marker, &ref
        ) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}

// MARK: - Tap

/// Zustand, den der Tap-Rückruf synchron braucht: „ist gerade ein Vorschlag
/// sichtbar?". Mit Sperre, damit die Entscheidung „schlucken" und das
/// Zurücksetzen atomar sind — ein zweites ⇥ direkt danach läuft durch.
final class AutocompleteTapBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var visible = false
    /// Nur vom Main-Thread gesetzt (Start/Stopp).
    var tap: CFMachPort?
    weak var controller: AutocompleteController?

    func setVisible(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        visible = value
    }

    /// Schluckt genau dann, wenn `AutocompleteKeyDecision.shouldSwallow` ja
    /// sagt, und setzt „sichtbar" im selben Schritt zurück.
    func consumeIfAccepting(keyCode: Int64, flags: CGEventFlags) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard AutocompleteKeyDecision.shouldSwallow(keyCode: keyCode, flags: flags, suggestionVisible: visible) else {
            return false
        }
        visible = false
        return true
    }
}

/// Der Rückruf macht keine Arbeit außer Flags lesen/setzen und die eigentliche
/// Reaktion auf den Main-Actor zu schicken (Design §3 „Denial of service").
/// Tasteninhalte werden nicht gelesen — nur Tastencode und Modifier für die
/// ⇥-Entscheidung; nichts wird gepuffert.
private let autocompleteTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let bridge = Unmanaged<AutocompleteTapBridge>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // macOS hat den Tap abgeschaltet → wieder einschalten.
        if let tap = bridge.tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if bridge.consumeIfAccepting(keyCode: keyCode, flags: flags) {
            Task { @MainActor in bridge.controller?.acceptShownSuggestion() }
            return nil
        }
        let restart = AutocompleteKeyDecision.restartsPause(keyCode: keyCode, flags: flags)
        Task { @MainActor in bridge.controller?.userTyped(restartPause: restart) }
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        Task { @MainActor in bridge.controller?.userClicked() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

/// Design §3: Weiterleitungen werden nicht verfolgt.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
