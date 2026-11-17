import Darwin
import Foundation
import OSLog
import Security

/// `deck.sock` for the Stream Deck plugin (docs/SECURE-DESIGN-stream-deck.md D2/D5). Same shape as the debug
/// channel's server: one client, everything on a private serial queue, every connection checked **before the first
/// byte is read** – the peer against the plugin requirement, and its parent process against Elgato's Stream Deck.
/// Invalid frames or commands close the connection. Never logs content.
final class DeckSocketServer: @unchecked Sendable {

    enum StartError: Error, Equatable {
        case directory, staleFile, pathTooLong, socket(Int32)
    }

    private static let log = Logger(subsystem: "com.tippi.app", category: "streamdeck")

    let socketPath: String
    private let requirement: SecRequirement
    private let parentRequirement: SecRequirement
    /// A checked command, or `nil` when the plugin disconnected. Called on the server's queue.
    private let onEvent: @Sendable (DeckWire.Command?) -> Void
    private let queue = DispatchQueue(label: "dev.mwlr.tippi.deck.socket")

    // Only on `queue`:
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clientFD: Int32 = -1
    private var clientSource: DispatchSourceRead?
    private var buffer = Data()
    private var windowStart = Date.distantPast
    private var windowCount = 0
    private var dropped = 0

    init(socketPath: String, requirement: SecRequirement, parentRequirement: SecRequirement,
         onEvent: @escaping @Sendable (DeckWire.Command?) -> Void) {
        self.socketPath = socketPath
        self.requirement = requirement
        self.parentRequirement = parentRequirement
        self.onEvent = onEvent
    }

    // MARK: File system

    /// Directory: a real folder (no link), ours, 0700.
    static func prepareDirectory(_ url: URL) -> Bool {
        let path = url.path
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT, mkdir(path, 0o700) == 0, lstat(path, &info) == 0 else { return false }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { return false }
        return chmod(path, 0o700) == 0
    }

    /// Remove an old socket file – only if it really is a socket and ours.
    private static func removeStaleSocket(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else { return false }
        return unlink(path) == 0
    }

    // MARK: Start / stop

    func start() throws {
        guard Self.prepareDirectory(URL(fileURLWithPath: socketPath).deletingLastPathComponent()) else {
            throw StartError.directory
        }
        guard Self.removeStaleSocket(socketPath) else { throw StartError.staleFile }
        var addr = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw StartError.pathTooLong }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.socket(errno) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 2) == 0 else {
            let err = errno
            close(fd)
            unlink(socketPath)
            throw StartError.socket(err)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        queue.sync {
            listenFD = fd
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptPending() }
            src.resume()
            listenSource = src
        }
        Self.log.notice("Stream Deck: socket open")
    }

    func stop() {
        queue.sync {
            closeClient(reason: nil)
            listenSource?.cancel()
            listenSource = nil
            if listenFD >= 0 {
                close(listenFD)
                listenFD = -1
                unlink(socketPath)
            }
        }
        Self.log.notice("Stream Deck: socket closed")
    }

    /// Send one status frame to the connected plugin (dropped when nobody is connected).
    func send(_ obj: [String: Any]) {
        queue.async { [weak self] in
            guard let self, self.clientFD >= 0, let data = DeckWire.frame(obj) else { return }
            let n = data.withUnsafeBytes { write(self.clientFD, $0.baseAddress, data.count) }
            if n != data.count { self.closeClient(reason: "write failed") }
        }
    }

    // MARK: Connections (on queue)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var status = Self.checkPeer(fd, requirement)
            if status == errSecSuccess { status = Self.checkParent(fd, parentRequirement) }
            guard status == errSecSuccess else {
                close(fd)
                Self.log.error("Stream Deck: connection refused (OSStatus \(status, privacy: .public))")
                continue
            }
            // A checked new connection replaces the old one.
            closeClient(reason: nil)
            // Status frames with the prompt list can exceed the 8 KB default send buffer of a Unix socket; a
            // non-blocking short write would close the connection.
            var sendBuffer: Int32 = 64 * 1024
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sendBuffer, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            clientFD = fd
            buffer = Data()
            if let ack = DeckWire.frame(["v": 1, "ok": true]) {
                _ = ack.withUnsafeBytes { write(fd, $0.baseAddress, ack.count) }
            }
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readClient() }
            src.resume()
            clientSource = src
            Self.log.notice("Stream Deck: plugin connected")
        }
    }

    /// Audit token of the peer → code → requirement. Audit token instead of PID: no race with reused PIDs.
    static func checkPeer(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard status == errSecSuccess, let code else { return status == errSecSuccess ? errSecCSGuestInvalid : status }
        return SecCodeCheckValidity(code, [], requirement)
    }

    /// The peer's parent process against `requirement` (D2.2b). PID from the audit token, parent PID from
    /// `proc_pidinfo`, parent code by PID – a parent has no audit token. Residual risk PID reuse: D9.
    static func checkParent(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let pid = pid_t(bitPattern: token.val.5)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else {
            return errSecCSGuestInvalid
        }
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: info.pbi_ppid)] as CFDictionary,
                                                    [], &code)
        guard status == errSecSuccess, let code else { return status == errSecSuccess ? errSecCSGuestInvalid : status }
        return SecCodeCheckValidity(code, [], requirement)
    }

    private func readClient() {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(clientFD, &chunk, chunk.count)
        if count == 0 { return closeClient(reason: "disconnected") }
        if count < 0 {
            if errno != EAGAIN { closeClient(reason: "read error") }
            return
        }
        buffer.append(contentsOf: chunk[0..<count])
        while clientFD >= 0 {
            switch DeckWire.nextFrame(&buffer, max: DeckWire.maxCommandBytes) {
            case .needMore:
                return
            case .invalid:
                return closeClient(reason: "invalid frame")
            case .message(let payload):
                guard let command = DeckWire.parse(payload) else { return closeClient(reason: "invalid command") }
                deliver(command)
            }
        }
    }

    private func closeClient(reason: String?) {
        let wasConnected = clientFD >= 0
        clientSource?.cancel()
        clientSource = nil
        if clientFD >= 0 {
            close(clientFD)
            clientFD = -1
        }
        buffer = Data()
        if let reason { Self.log.notice("Stream Deck: \(reason, privacy: .public)") }
        if wasConnected { onEvent(nil) }
    }

    /// At most `maxPerSecond` commands per second; the rest is dropped and counted (count only, never content).
    private func deliver(_ command: DeckWire.Command) {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1 {
            if dropped > 0 { Self.log.notice("Stream Deck: \(self.dropped, privacy: .public) commands dropped (rate)") }
            windowStart = now
            windowCount = 0
            dropped = 0
        }
        windowCount += 1
        if windowCount <= DeckWire.maxPerSecond { onEvent(command) } else { dropped += 1 }
    }
}
