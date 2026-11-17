import AppKit
import OSLog
import Security

/// Settings → General → Stream Deck. Off by default; off = no socket at all (docs/SECURE-DESIGN-stream-deck.md D1).
enum StreamDeckSettings {
    static let enabledKey = "streamDeck.enabled"
    /// Tests swap this for a throwaway store – never write `UserDefaults.standard` in a test.
    static var store: UserDefaults = .standard

    static var isEnabled: Bool {
        get { store.bool(forKey: enabledKey) }
        set { store.set(newValue, forKey: enabledKey) }
    }
}

/// Owns `deck.sock` while „Stream Deck“ is on, hands checked commands to `onCommand` and pushes Tippi's state back –
/// only what changed. Never logs content.
@MainActor
final class StreamDeckLink: ObservableObject {

    private static let log = Logger(subsystem: "com.tippi.app", category: "streamdeck")

    /// Plugin connected right now (shown in Settings).
    @Published private(set) var connected = false
    /// Version the plugin reported when it is older than this Tippi (Settings offers „install again“).
    @Published private(set) var outdatedPlugin: String?

    var onCommand: (DeckWire.Command) -> Void = { _ in }
    var onDisconnect: () -> Void = {}
    /// Current state; prompts and modes are only asked for every few ticks (they rarely change).
    var status: (_ withPrompts: Bool) -> DeckWire.Status = { _ in DeckWire.Status() }

    private var server: DeckSocketServer?
    private var watching = false
    private var timer: Timer?
    private var tickCount = 0
    private var last: DeckWire.Status?
    private var lastPrompts: [DeckWire.Item] = []
    private var lastModes: [DeckWire.Item] = []

    static var socketPath: String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tippi/\(DeckWire.socketName)").path
    }

    /// Start or stop to match the setting.
    func apply() {
        if StreamDeckSettings.isEnabled { start() } else { stop() }
    }

    private func start() {
        guard server == nil, let path = Self.socketPath else { return }
        var req: SecRequirement?
        var parent: SecRequirement?
        guard SecRequirementCreateWithString(DeckWire.pluginRequirement as CFString, [], &req) == errSecSuccess, let req,
              SecRequirementCreateWithString(DeckWire.streamDeckRequirement as CFString, [], &parent) == errSecSuccess,
              let parent else {
            return Self.log.error("Stream Deck: requirement invalid")
        }
        let s = DeckSocketServer(socketPath: path, requirement: req, parentRequirement: parent) { [weak self] c in
            Task { @MainActor in self?.receive(c) }
        }
        do {
            try s.start()
            server = s
        } catch {
            Self.log.error("Stream Deck off: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        disconnected()
    }

    private func receive(_ c: DeckWire.Command?) {
        guard let c else { return disconnected() }
        connected = true
        switch c {
        case .hello(let version):
            let own = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            outdatedPlugin = DeckWire.isOutdated(plugin: version, current: own) ? version : nil
        case .watch:
            watching = true
            last = nil
            startTimer()
            push(force: true)
        case .dictation, .run, .prompt:
            onCommand(c)
            push(force: false)
        }
    }

    private func disconnected() {
        let was = connected
        connected = false
        watching = false
        timer?.invalidate()
        timer = nil
        last = nil
        if was {
            Self.log.notice("Stream Deck: plugin disconnected")
            onDisconnect()
        }
    }

    /// While watched: 10 checks per second only during a dictation (level bar), otherwise one per second – Stream Deck
    /// runs all day, and a constant 10 Hz main-thread timer costs battery (code audit 17.11.). Commands from the plugin
    /// push at once; a change made elsewhere (hot key, menu) shows up within a second. Only changes are sent.
    private func startTimer(fast: Bool = false) {
        let interval: TimeInterval = fast ? 0.1 : 1.0
        if let t = timer, t.timeInterval == interval { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            // concurrency-lint: on-main Timer is added to RunLoop.main directly below
            MainActor.assumeIsolated { [weak self] in self?.push(force: false) }
        }
        t.tolerance = interval * 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func push(force: Bool) {
        guard watching, let server else { return }
        tickCount += 1
        let withPrompts = force || last == nil || tickCount % 5 == 0
        var s = status(withPrompts)
        if withPrompts { lastPrompts = s.prompts; lastModes = s.modes } else { s.prompts = lastPrompts; s.modes = lastModes }
        startTimer(fast: s.dictation != .idle)
        guard force || s != last else { return }
        last = s
        server.send(DeckWire.encode(s))
    }

    // MARK: Install the plugin (D6)

    nonisolated static var pluginSource: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(DeckWire.pluginFolder, isDirectory: true)
    }

    enum InstallError: Error, Equatable { case missing, unsigned, pack }

    /// Packs the plugin folder with `ditto` (fixed arguments, no shell) into a fresh 0700 temp folder and hands the
    /// package to Stream Deck, which asks the user itself. Tippi never writes into Elgato's folders. Only a plugin
    /// with a valid signature of our own is handed over.
    static func installPlugin() -> Result<Void, InstallError> {
        guard let src = pluginSource, FileManager.default.fileExists(atPath: src.path) else { return .failure(.missing) }
        guard isGenuinePlugin(src.appendingPathComponent(DeckWire.executable)) else { return .failure(.unsigned) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TippiDeck-\(UUID().uuidString)", isDirectory: true)
        let package = dir.appendingPathComponent("Tippi.streamDeckPlugin")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", src.path, package.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw InstallError.pack }
        } catch {
            log.error("Stream Deck: package not built")
            return .failure(.pack)
        }
        NSWorkspace.shared.open(package)
        log.notice("Stream Deck: plugin package handed over")
        return .success(())
    }

    nonisolated static func isGenuinePlugin(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(DeckWire.pluginRequirement as CFString, [], &req) == errSecSuccess,
              let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
