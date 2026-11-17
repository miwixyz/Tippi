import Darwin
import Foundation
import OSLog
import Security

/// Connection to Tippi's `deck.sock` (docs/SECURE-DESIGN-stream-deck.md D2.3). Before any command leaves, the plugin
/// checks the listening process by audit token against Tippi's Developer-ID requirement and waits for Tippi's `ok`.
/// Logs only fixed texts via os_log – never stdout/stderr (Stream Deck keeps a log file of that per plugin).
@MainActor
final class TippiSocket {

    static let log = Logger(subsystem: DeckWire.pluginID, category: "tippi")
    static let ackTimeout: TimeInterval = 0.5

    var onStatus: (DeckWire.Status) -> Void = { _ in }
    var onConnectionChange: (Bool) -> Void = { _ in }

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var buffer = Data()

    var isConnected: Bool { fd >= 0 }

    static var path: String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tippi/\(DeckWire.socketName)").path
    }

    /// true = connected, other side checked, `ok` received.
    @discardableResult
    func connect() -> Bool {
        guard fd < 0, let path = Self.path else { return isConnected }
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var receiveBuffer: Int32 = 64 * 1024
        setsockopt(s, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, socklen_t(MemoryLayout<Int32>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, len) }
        }
        guard connected == 0 else { Darwin.close(s); return false }
        let status = Self.checkServer(s)
        guard status == errSecSuccess else {
            Darwin.close(s)
            Self.log.error("other side is not the real Tippi (OSStatus \(status, privacy: .public)) – nothing sent")
            return false
        }
        guard readAck(s) else {
            Darwin.close(s)
            Self.log.notice("Tippi did not confirm")
            return false
        }
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
        fd = s
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readIncoming() } }
        src.resume()
        source = src
        Self.log.notice("connected to Tippi")
        onConnectionChange(true)
        return true
    }

    nonisolated static func checkServer(_ fd: Int32) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(DeckWire.tippiRequirement as CFString, [], &req) == errSecSuccess, let req else {
            return errSecCSReqInvalid
        }
        return SecCodeCheckValidity(code, [], req)
    }

    private func readAck(_ s: Int32) -> Bool {
        var tv = timeval(tv_sec: 0, tv_usec: Int32(Self.ackTimeout * 1_000_000))
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(s, &chunk, chunk.count)
            guard n > 0 else { return false }
            buf.append(contentsOf: chunk[0..<n])
            switch DeckWire.nextFrame(&buf) {
            case .needMore: continue
            case .invalid: return false
            case .message(let payload):
                guard DeckWire.isAck(payload) else { return false }
                buffer = buf
                return true
            }
        }
    }

    func send(_ c: DeckWire.Command) {
        guard fd >= 0, let data = DeckWire.frame(DeckWire.encode(c), max: DeckWire.maxCommandBytes) else { return }
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        if n != data.count { close(reason: "write error") }
    }

    private func readIncoming() {
        var chunk = [UInt8](repeating: 0, count: DeckWire.maxFrame)
        let n = read(fd, &chunk, chunk.count)
        if n == 0 { return close(reason: "Tippi disconnected") }
        if n < 0 { return errno == EAGAIN ? () : close(reason: "read error") }
        buffer.append(contentsOf: chunk[0..<n])
        while fd >= 0 {
            switch DeckWire.nextFrame(&buffer) {
            case .needMore: return
            case .invalid: return close(reason: "invalid frame")
            case .message(let payload):
                guard let s = DeckWire.parseStatus(payload) else { return close(reason: "invalid message") }
                onStatus(s)
            }
        }
    }

    func close(reason: String) {
        guard fd >= 0 else { return }
        source?.cancel()
        source = nil
        Darwin.close(fd)
        fd = -1
        buffer = Data()
        Self.log.notice("\(reason, privacy: .public)")
        onConnectionChange(false)
    }
}
