import Darwin
import Foundation
import OSLog
import Security

// TippiDeck – Stream Deck plugin for Tippi (docs/SECURE-DESIGN-stream-deck.md). Turns keys, dials and the touch strip into
// Tippi commands and shows Tippi's state. No permissions, no microphone, no text. Never writes to stdout/stderr (Stream Deck
// keeps a log file of that per plugin, Gnotchi M6) – only os_log with fixed texts.

let log = Logger(subsystem: DeckWire.pluginID, category: "plugin")

/// Started by Elgato's Stream Deck? Otherwise quit silently (Tippi checks the same again, D2.2b).
func parentIsStreamDeck() -> Bool {
    var req: SecRequirement?
    guard SecRequirementCreateWithString(DeckWire.streamDeckRequirement as CFString, [], &req) == errSecSuccess, let req else { return false }
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: NSNumber(value: getppid())] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return false }
    return SecCodeCheckValidity(code, [], req) == errSecSuccess
}

/// Arguments from Stream Deck: `-port N -pluginUUID … -registerEvent … -info …`.
struct DeckArgs {
    let port: Int
    let uuid: String
    let register: String
    let german: Bool
}

func streamDeckArguments(_ argv: [String]) -> DeckArgs? {
    var a: [String: String] = [:]
    var i = 1
    while i + 1 < argv.count { a[argv[i]] = argv[i + 1]; i += 2 }
    guard let p = a["-port"].flatMap(Int.init), (1...65_535).contains(p), let u = a["-pluginUUID"], let r = a["-registerEvent"] else {
        return nil
    }
    var german = true
    if let info = a["-info"]?.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: info) as? [String: Any],
       let lang = (obj["application"] as? [String: Any])?["language"] as? String {
        german = lang.hasPrefix("de")
    }
    return DeckArgs(port: p, uuid: u, register: r, german: german)
}

/// One action on the device.
struct DeckAction {
    enum Kind { case dictation, prompt, tool, toggle }
    let kind: Kind
    var onDial: Bool
    var dictKind: DeckDictKind = .dictation
    var press: DeckPress = .toggle
    var mode: DeckWire.ModeSlot = .standard
    /// Prompt id from the settings; empty = open Tippi's popup.
    var promptID = ""
    /// Dial: prompt currently highlighted (index into Tippi's list).
    var browse: Int?
    var tool: DeckWire.Action = .popup
    var toggle: DeckSwitch = .pause
    var marquee = Marquee()
    var track: TrackImage?
    var lastFeedback: [String: String] = [:]
}

@MainActor
final class Plugin {

    static let dictationAction = "dev.mwlr.tippi.deck.dictation"
    static let promptAction = "dev.mwlr.tippi.deck.prompt"
    static let toolAction = "dev.mwlr.tippi.deck.tool"
    static let toggleAction = "dev.mwlr.tippi.deck.toggle"

    private let task: URLSessionWebSocketTask
    private let tippi = TippiSocket()
    private let german: Bool
    private var actions: [String: DeckAction] = [:]
    private var status: DeckWire.Status?
    private var tick: Timer?
    private var reconnect: Timer?

    init(port: Int, uuid: String, register: String, german: Bool) {
        self.german = german
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
        sendDeck(["event": register, "uuid": uuid])
        tippi.onStatus = { [weak self] s in self?.received(s) }
        tippi.onConnectionChange = { [weak self] up in self?.connectionChanged(up) }
        receiveLoop()
        reconnect = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tryConnect() }
        }
        reconnect?.tolerance = 0.5
    }

    private func tr(_ de: String, _ en: String) -> String { german ? de : en }

    // MARK: Stream Deck

    private func sendDeck(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { error in if error != nil { log.error("sending to Stream Deck failed") } }
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .failure:
                    log.notice("Stream Deck gone – exit")
                    exit(0)
                case .success(let msg):
                    if case .string(let s) = msg, let d = s.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self?.handle(obj)
                    }
                    self?.receiveLoop()
                }
            }
        }
    }

    private func kind(of action: String) -> DeckAction.Kind? {
        switch action {
        case Self.dictationAction: .dictation
        case Self.promptAction: .prompt
        case Self.toolAction: .tool
        case Self.toggleAction: .toggle
        default: nil
        }
    }

    private func handle(_ obj: [String: Any]) {
        guard let event = obj["event"] as? String else { return }
        let ctx = obj["context"] as? String
        let payload = obj["payload"] as? [String: Any] ?? [:]
        switch event {
        case "willAppear", "didReceiveSettings":
            guard let ctx, let action = obj["action"] as? String, let kind = kind(of: action) else { return }
            configure(ctx, kind: kind, payload: payload, appearing: event == "willAppear")
        case "willDisappear":
            guard let ctx else { return }
            // A key that disappears while holding (page switch) still ends the dictation.
            if let a = actions[ctx], a.kind == .dictation, a.press == .hold, status?.dictation == .recording {
                tippi.send(.dictation(.holdEnd, mode: a.mode))
            }
            actions[ctx] = nil
            updateTickTimer()
        case "keyDown":
            guard let ctx, let a = actions[ctx] else { return }
            guard tippi.isConnected else { sendDeck(["event": "showAlert", "context": ctx]); return }
            press(a, down: true)
        case "keyUp":
            guard let ctx, let a = actions[ctx] else { return }
            press(a, down: false)
        case "dialDown":
            guard let ctx, let a = actions[ctx], a.kind == .dictation, a.press == .hold else { return }
            guard tippi.isConnected else { sendDeck(["event": "showAlert", "context": ctx]); return }
            tippi.send(.dictation(.holdStart, mode: a.mode))
        case "dialUp":
            guard let ctx, let a = actions[ctx] else { return }
            guard tippi.isConnected else { sendDeck(["event": "showAlert", "context": ctx]); return }
            switch a.kind {
            case .dictation:
                tippi.send(.dictation(a.press == .hold ? .holdEnd : .toggle, mode: a.mode))
            case .prompt:
                runPrompt(a)
            case .tool, .toggle:
                break
            }
        case "dialRotate":
            guard let ctx, let a = actions[ctx], let ticks = payload["ticks"] as? Int, ticks != 0 else { return }
            rotate(ctx, a, ticks: ticks)
        case "touchTap":
            guard let ctx, let a = actions[ctx] else { return }
            guard tippi.isConnected else { sendDeck(["event": "showAlert", "context": ctx]); return }
            switch a.kind {
            case .dictation: tippi.send(.dictation(.toggle, mode: a.mode))
            case .prompt: tippi.send(.run(.popup))
            case .tool, .toggle: break
            }
        case "sendToPlugin":
            // Property inspector of one of our actions asks for the lists (prompt and mode names) to fill its menus.
            guard let ctx, let action = obj["action"] as? String, kind(of: action) != nil else { return }
            sendLists(ctx)
        default:
            break
        }
    }

    /// Read an action's settings – only the fixed vocabulary; anything else → default.
    private func configure(_ ctx: String, kind: DeckAction.Kind, payload: [String: Any], appearing: Bool) {
        let settings = payload["settings"] as? [String: Any] ?? [:]
        let onDial = (payload["controller"] as? String) == "Encoder"
        var a = actions[ctx] ?? DeckAction(kind: kind, onDial: onDial)
        if appearing { a.onDial = onDial }
        if a.onDial, a.track == nil { a.track = TrackImage() }
        a.dictKind = (settings["kind"] as? String).flatMap(DeckDictKind.init(rawValue:)) ?? .dictation
        a.press = (settings["press"] as? String).flatMap(DeckPress.init(rawValue:)) ?? .toggle
        a.mode = (settings["mode"] as? String).flatMap(DeckWire.ModeSlot.init(rawValue:)) ?? .standard
        a.promptID = (settings["prompt"] as? String).flatMap { DeckWire.isValidID($0) ? $0 : nil } ?? ""
        a.tool = (settings["tool"] as? String).flatMap(DeckWire.Action.init(rawValue:))
            .flatMap { DeckLogic.tools.contains($0) ? $0 : nil } ?? .popup
        a.toggle = (settings["toggle"] as? String).flatMap(DeckSwitch.init(rawValue:)) ?? .pause
        a.lastFeedback = [:]
        actions[ctx] = a
        tryConnect()
        render(ctx)
    }

    private func press(_ a: DeckAction, down: Bool) {
        switch a.kind {
        case .dictation:
            if a.dictKind == .dictation, a.press == .hold {
                tippi.send(.dictation(down ? .holdStart : .holdEnd, mode: a.mode))
                return
            }
            guard down else { return }
            switch a.dictKind {
            case .dictation: tippi.send(.dictation(.toggle, mode: a.mode))
            case .mail: tippi.send(.run(.mailDictation))
            case .voiceNote: tippi.send(.run(.voiceNote))
            case .reply: tippi.send(.run(.reply))
            }
        case .prompt:
            if down { runPrompt(a) }
        case .tool:
            if down { tippi.send(.run(a.tool)) }
        case .toggle:
            guard down else { return }
            switch a.toggle {
            case .pause: tippi.send(.run(.pause))
            case .autocomplete: tippi.send(.run(.autocomplete))
            case .language: tippi.send(.run(.language))
            }
        }
    }

    /// Dial: the highlighted prompt; key (or dial never turned): the prompt from the settings; empty → Tippi's popup.
    private func runPrompt(_ a: DeckAction) {
        let list = status?.prompts ?? []
        if let i = a.browse, list.indices.contains(i) { return tippi.send(.prompt(id: list[i].id)) }
        if a.promptID.isEmpty { return tippi.send(.run(.popup)) }
        tippi.send(.prompt(id: a.promptID))
    }

    private func rotate(_ ctx: String, _ a: DeckAction, ticks: Int) {
        switch a.kind {
        case .dictation:
            // Modes offered: standard + every slot Tippi has an assignment for.
            let slots: [DeckWire.ModeSlot] = [.standard] + (status?.modes ?? []).compactMap { DeckWire.ModeSlot(rawValue: $0.id) }
            guard let i = DeckLogic.step(count: slots.count, from: slots.firstIndex(of: a.mode), by: ticks > 0 ? 1 : -1) else { return }
            actions[ctx]?.mode = slots[i]
            saveSettings(ctx)
        case .prompt:
            let list = status?.prompts ?? []
            let start = a.browse ?? list.firstIndex { $0.id == a.promptID }
            actions[ctx]?.browse = DeckLogic.step(count: list.count, from: start, by: ticks > 0 ? 1 : -1)
        case .tool, .toggle:
            return
        }
        render(ctx)
    }

    /// Keep the dial's chosen mode in its settings (survives restarts).
    private func saveSettings(_ ctx: String) {
        guard let a = actions[ctx] else { return }
        let s: [String: Any] = ["kind": a.dictKind.rawValue, "press": a.press.rawValue, "mode": a.mode.rawValue]
        sendDeck(["event": "setSettings", "context": ctx, "payload": s])
    }

    private func sendLists(_ ctx: String) {
        let prompts = (status?.prompts ?? []).map { ["id": $0.id, "title": $0.title] }
        let modes = (status?.modes ?? []).map { ["id": $0.id, "title": $0.title] }
        sendDeck(["event": "sendToPropertyInspector", "context": ctx,
                  "payload": ["prompts": prompts, "modes": modes, "connected": tippi.isConnected]])
    }

    // MARK: Tippi

    private func tryConnect() {
        guard !tippi.isConnected, !actions.isEmpty else { return }
        tippi.connect()
    }

    private func connectionChanged(_ up: Bool) {
        if up {
            tippi.send(.hello(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"))
            tippi.send(.watch)
        } else {
            status = nil
        }
        for ctx in actions.keys { actions[ctx]?.lastFeedback = [:]; render(ctx) }
    }

    private func received(_ s: DeckWire.Status) {
        status = s
        for ctx in actions.keys { render(ctx) }
    }

    // MARK: Rendering

    private var imageCache: [String: String] = [:]

    /// PNG from the plugin folder as `data:` URL (read once, then from memory).
    private func imageData(_ name: String) -> String? {
        if let hit = imageCache[name] { return hit }
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("imgs/\(name)@2x.png")) else { return nil }
        let url = "data:image/png;base64," + d.base64EncodedString()
        imageCache[name] = url
        return url
    }

    private func renderKey(_ ctx: String, _ a: inout DeckAction, image: String, title: String) {
        if a.lastFeedback["image"] != image, let data = imageData(image) {
            sendDeck(["event": "setImage", "context": ctx, "payload": ["image": data, "target": 0]])
            a.lastFeedback["image"] = image
        }
        if a.lastFeedback["title"] != title {
            sendDeck(["event": "setTitle", "context": ctx, "payload": ["title": title, "target": 0]])
            a.lastFeedback["title"] = title
        }
    }

    private func renderStrip(_ ctx: String, _ a: inout DeckAction, name: String, value: String, line: String, bar: Int) {
        let width = a.track?.prepare(line, gap: a.marquee.gap) ?? 0
        a.marquee.set(key: line, contentWidth: width)
        let fb: [String: String] = ["name": name, "value": value, "track": "\(line)|\(a.marquee.offset)", "bar": String(bar)]
        guard fb != a.lastFeedback else { return }
        var payload: [String: Any] = ["name": name, "value": value, "bar": ["value": bar]]
        if fb["track"] != a.lastFeedback["track"], let img = a.track?.frame(offset: a.marquee.offset) { payload["track"] = img }
        sendDeck(["event": "setFeedback", "context": ctx, "payload": payload])
        a.lastFeedback = fb
    }

    private func modeTitle(_ slot: DeckWire.ModeSlot) -> String {
        guard slot != .standard else { return tr("Normal", "Normal") }
        return status?.modes.first { $0.id == slot.rawValue }?.title ?? tr("Normal", "Normal")
    }

    private func kindTitle(_ k: DeckDictKind) -> String {
        switch k {
        case .dictation: tr("Diktat", "Dictate")
        case .mail: tr("Mail", "Mail")
        case .voiceNote: tr("Notiz", "Voice note")
        case .reply: tr("Antwort", "Reply")
        }
    }

    private func toolTitle(_ t: DeckWire.Action) -> String {
        switch t {
        case .popup: tr("Tippi", "Tippi")
        case .translate: tr("Übersetzen", "Translate")
        case .emoji: tr("Emoji", "Emoji")
        case .notes: tr("Notizen", "Notes")
        case .quickNotes: tr("Schnell-\nnotiz", "Quick\nnote")
        case .screenText: tr("Text vom\nBildschirm", "Screen\ntext")
        case .password: tr("Passwort", "Password")
        default: ""
        }
    }

    private func toolImage(_ t: DeckWire.Action) -> String {
        switch t {
        case .popup: "key-popup"
        case .translate: "key-translate"
        case .emoji: "key-emoji"
        case .notes: "key-notes"
        case .quickNotes: "key-quicknote"
        case .screenText: "key-screentext"
        case .password: "key-password"
        default: "key-popup"
        }
    }

    private func render(_ ctx: String) {
        guard var a = actions[ctx] else { return }
        let s = status
        let connected = tippi.isConnected
        let off = tr("Tippi aus", "Tippi off")
        switch a.kind {
        case .dictation where !a.onDial:
            var title = kindTitle(a.dictKind)
            if a.dictKind == .dictation, a.mode != .standard {
                title += "\n" + (DeckLogic.wrap(modeTitle(a.mode), width: 9).components(separatedBy: "\n").first ?? "")
            }
            renderKey(ctx, &a, image: DeckLogic.dictationImage(a.dictKind, status: s, connected: connected),
                      title: connected ? title : off)
        case .dictation:
            let mine = s.map { DeckLogic.matches(.dictation, source: $0.source) } ?? false
            let value: String
            if !connected { value = "" } else if !(s?.ready ?? false) { value = tr("aus", "off") } else {
                switch (mine ? s?.dictation : .idle) ?? .idle {
                case .idle: value = tr("bereit", "ready")
                case .recording: value = tr("● Aufnahme", "● Recording")
                case .transcribing: value = tr("schreibt …", "writing …")
                }
            }
            let line = connected ? tr("Modus: ", "Mode: ") + modeTitle(a.mode) : tr("Tippi nicht verbunden", "Tippi not connected")
            let bar = mine && s?.dictation == .recording ? (s?.level ?? 0) * 100 / DeckWire.maxLevel : 0
            renderStrip(ctx, &a, name: tr("Diktat", "Dictation"), value: value, line: line, bar: bar)
        case .prompt where !a.onDial:
            let list = s?.prompts ?? []
            let title: String
            if a.promptID.isEmpty { title = "Tippi" } else if let p = list.first(where: { $0.id == a.promptID }) {
                title = DeckLogic.wrap(p.title)
            } else { title = s == nil ? tr("Prompt", "Prompt") : tr("Prompt\nfehlt", "Prompt\nmissing") }
            renderKey(ctx, &a, image: a.promptID.isEmpty ? "key-popup" : "key-prompt", title: connected ? title : off)
        case .prompt:
            let list = s?.prompts ?? []
            let i = a.browse ?? list.firstIndex { $0.id == a.promptID }
            let line: String
            if !connected { line = tr("Tippi nicht verbunden", "Tippi not connected") } else if let i, list.indices.contains(i) {
                line = list[i].title
            } else { line = tr("Drehen = Prompt", "Turn = prompt") }
            let pos = i.map { "\($0 + 1)/\(list.count)" } ?? ""
            let bar = i.map { list.count > 1 ? $0 * 100 / (list.count - 1) : 100 } ?? 0
            renderStrip(ctx, &a, name: tr("Prompt", "Prompt"), value: pos, line: line, bar: bar)
        case .tool:
            renderKey(ctx, &a, image: toolImage(a.tool), title: connected ? toolTitle(a.tool) : off)
        case .toggle:
            let image: String
            let title: String
            switch a.toggle {
            case .pause:
                let paused = s?.paused ?? false
                image = paused ? "key-resume" : "key-pause"
                title = paused ? tr("Pausiert", "Paused") : tr("Pause", "Pause")
            case .autocomplete:
                let on = s?.autocomplete ?? false
                image = on ? "key-autocomplete-on" : "key-autocomplete"
                title = tr("Vervollst.", "Complete") + "\n" + (on ? tr("an", "on") : tr("aus", "off"))
            case .language:
                let lang = s?.language ?? "auto"
                image = "key-language"
                title = lang == "auto" ? tr("Sprache\nAuto", "Language\nAuto") : tr("Sprache\n", "Language\n") + lang.uppercased()
            }
            renderKey(ctx, &a, image: image, title: connected ? title : off)
        }
        actions[ctx] = a
        updateTickTimer()
    }

    /// Marquee clock only while a dial strip really scrolls (Stream Deck runs all day – no idle wake-ups).
    private func updateTickTimer() {
        let needed = actions.values.contains { $0.onDial && $0.marquee.scrolls }
        if needed, tick == nil {
            tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in self?.scrollTick() }
            }
            tick?.tolerance = 0.01
        } else if !needed, let t = tick {
            t.invalidate()
            tick = nil
        }
    }

    private func scrollTick() {
        for (ctx, a) in actions where a.onDial && a.marquee.scrolls {
            var m = a.marquee
            let moved = m.tick()
            actions[ctx]?.marquee = m   // write back during the hold too, or the hold never counts down (Gnotchi M7)
            guard moved, let img = a.track?.frame(offset: m.offset) else { continue }
            sendDeck(["event": "setFeedback", "context": ctx, "payload": ["track": img]])
            actions[ctx]?.lastFeedback["track"] = "\(m.key)|\(m.offset)"
        }
    }
}

guard parentIsStreamDeck() else {
    log.error("not started by Stream Deck – exit")
    exit(0)
}
guard let args = streamDeckArguments(CommandLine.arguments) else {
    log.error("Stream Deck arguments missing – exit")
    exit(1)
}
let plugin = MainActor.assumeIsolated { Plugin(port: args.port, uuid: args.uuid, register: args.register, german: args.german) }
withExtendedLifetime(plugin) { RunLoop.main.run() }
