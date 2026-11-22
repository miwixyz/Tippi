import Combine
import CryptoKit
import Darwin
import Foundation
import OSLog
import Security

/// Settings → General → Desk device (Tippi-Firmware 0.9, design: tippi-firmware SICHERHEIT.md „Entwurf 0.9“).
///
/// Tippi's desk gadget shows the dictation state on its face: listening, thinking, done. **Off by default.** Only the
/// state word leaves Tippi – never text, audio, app names or anything the user dictated. Each request is signed with
/// HMAC-SHA256 over `time + "\n" + body` with a key from the keychain; the key itself never goes over the network.
/// The gadget rejects old, repeated and unsigned requests. Never logs the key.
enum DeskDeviceSettings {
    static let enabledKey = "deskDevice.enabled"
    static let hostKey = "deskDevice.host"
    static let defaultHost = "tippi.local"
    /// Tests swap this for a throwaway store – never write `UserDefaults.standard` in a test.
    static var store: UserDefaults = .standard

    static var isEnabled: Bool { store.bool(forKey: enabledKey) }
    static var host: String { validHost(store.string(forKey: hostKey) ?? "") ?? defaultHost }

    // MARK: Pure parts (tested)

    enum State: String, Sendable { case ruhe, hoert, denkt, fertig, fehler }

    /// Host name or IPv4 only: letters, digits, dots and dashes, ≤ 64 characters. No scheme, port, path or user.
    static func validHost(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(t.count),
              t.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "-" }),
              !t.hasPrefix("."), !t.hasPrefix("-") else { return nil }
        return t
    }

    /// Printable ASCII without spaces, 20–128 characters (the gadget accepts exactly that).
    static func validKey(_ key: String) -> Bool {
        (20...128).contains(key.count) && key.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }

    static func body(_ state: State) -> Data { Data("{\"z\":\"\(state.rawValue)\"}".utf8) }

    static func signature(key: String, time: Int, body: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(time)\n".utf8) + body, using: SymmetricKey(data: Data(key.utf8)))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// What the face shows for a dictation step. `previous` decides „done“: only after a transcription.
    static func state(for dictation: DictationController.State, previous: DictationController.State?) -> State {
        switch dictation {
        case .recording: return .hoert
        case .transcribing: return .denkt
        case .idle: return previous == .transcribing ? .fertig : .ruhe
        }
    }
}

/// Own keychain item, not synced (no `kSecAttrSynchronizable`).
enum DeskDeviceKeychain {
    nonisolated(unsafe) private static let query: [String: Any] = [   // read-only after init
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.tippi.app.deskdevice",
        kSecAttrAccount as String: "hmac",
    ]

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count <= 128,
              let key = String(data: data, encoding: .utf8), DeskDeviceSettings.validKey(key) else { return nil }
        return key
    }

    static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Follows the dictation state and sends each change, plus a heartbeat every 30 s (the gadget falls back to rest after
/// 60 s without news – Tippi quit, Mac asleep).
@MainActor
final class DeskDeviceLink: ObservableObject {

    private static let log = Logger(subsystem: "com.tippi.app", category: "deskdevice")

    /// Last result for Settings. Own apps never fail silently.
    @Published private(set) var status: String?

    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private var current: DeskDeviceSettings.State = .ruhe
    private var lastDictation: DictationController.State?
    private var lastTime = 0
    private var lastCode: Int?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    /// Start or stop to match the setting.
    func apply(dictation: DictationController) {
        cancellable = nil
        timer?.invalidate()
        timer = nil
        guard DeskDeviceSettings.isEnabled else { status = nil; return }
        cancellable = dictation.$state.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] s in
            // concurrency-lint: on-main receive(on: DispatchQueue.main) directly above
            MainActor.assumeIsolated { self?.changed(s) }
        }
        let t = Timer(timeInterval: 30, repeats: true) { _ in
            // concurrency-lint: on-main Timer is added to RunLoop.main directly below
            MainActor.assumeIsolated { [weak self] in self.map { $0.send($0.current) } }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Send once now (Settings: after saving the key).
    func test() { send(.fertig) }

    private func changed(_ s: DictationController.State) {
        let state = DeskDeviceSettings.state(for: s, previous: lastDictation)
        lastDictation = s
        current = state == .fertig ? .ruhe : state
        send(state)
    }

    private func send(_ state: DeskDeviceSettings.State) {
        guard let key = DeskDeviceKeychain.read() else { status = String(localized: "settings.deskDevice.noKey"); return }
        // Strictly increasing time (the gadget rejects repeats); two changes in one second get the next second.
        let now = max(Int(Date().timeIntervalSince1970), lastTime + 1)
        lastTime = now
        let body = DeskDeviceSettings.body(state)
        let signature = DeskDeviceSettings.signature(key: key, time: now, body: body)
        let host = DeskDeviceSettings.host
        Task.detached { [session] in
            // IPv4 only: macOS waits ~5 s for an IPv6 answer on .local otherwise (measured 22.11.)
            guard let ip = Self.ipv4(host), let url = URL(string: "http://\(ip)/zustand") else {
                await MainActor.run { self.status = String(localized: "settings.deskDevice.notFound") }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(String(now), forHTTPHeaderField: "x-tippi-zeit")
            request.setValue(signature, forHTTPHeaderField: "x-tippi-sig")
            let code = (try? await session.data(for: request)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            await MainActor.run {
                switch code {
                case 200: self.status = String(localized: "settings.deskDevice.ok")
                case 401: self.status = String(localized: "settings.deskDevice.rejected")
                case .some(let c): self.status = String(format: String(localized: "settings.deskDevice.error"), c)
                case nil: self.status = String(localized: "settings.deskDevice.notFound")
                }
                // Only when the result changes: the heartbeat runs every 30 s, an absent gadget would flood the log
                if code != self.lastCode { Self.log.notice("desk device: send \(code ?? -1, privacy: .public)") }
                self.lastCode = code
            }
        }
    }

    nonisolated private static func ipv4(_ host: String) -> String? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "80", &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        var addr = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buf)
    }
}
