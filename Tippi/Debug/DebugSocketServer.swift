#if DEBUG
import Darwin
import Foundation
import OSLog
import Security

/// Lokaler Socket des Befehlskanals (docs/SECURE-DESIGN-befehlskanal.md B6/B7) – Übertragung von Kallis
/// `DebugSocketServer` (K1): ein Client, jede Nachricht zählt, höchstens 10 je Sekunde.
///
/// Alles auf einer eigenen seriellen Warteschlange; nach außen nur `onCommand` mit geprüften Befehlen. Jede
/// Verbindung wird **vor dem ersten gelesenen Byte** über das Audit-Token der Gegenseite gegen `requirement`
/// geprüft. Ungültige Rahmen oder Befehle: Verbindung zu, keine Antwort. Nie Inhalte ins Protokoll.
final class DebugSocketServer: @unchecked Sendable {

    enum StartError: Error, Equatable {
        case directory, staleFile, pathTooLong, socket(Int32)
    }

    static let maxPerSecond = 10
    private static let log = Logger(subsystem: "com.tippi.app", category: "debug")

    let socketPath: String
    private let requirement: SecRequirement
    private let onCommand: @Sendable (DebugCommand) -> Void
    private let queue = DispatchQueue(label: "dev.mwlr.tippi.debug.socket")

    // Nur auf `queue`:
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clientFD: Int32 = -1
    private var clientSource: DispatchSourceRead?
    private var buffer = Data()
    private var windowStart = Date.distantPast
    private var windowCount = 0

    init(socketPath: String, requirement: SecRequirement, onCommand: @escaping @Sendable (DebugCommand) -> Void) {
        self.socketPath = socketPath
        self.requirement = requirement
        self.onCommand = onCommand
    }

    // MARK: Dateisystem

    /// Ordner anlegen bzw. prüfen: echter Ordner (kein Link), gehört uns, Rechte 0700.
    static func prepareDirectory(_ url: URL) -> Bool {
        let path = url.path
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT, mkdir(path, 0o700) == 0, lstat(path, &info) == 0 else { return false }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { return false }
        return chmod(path, 0o700) == 0
    }

    /// Alte Socket-Datei entfernen – nur, wenn es wirklich ein Socket ist und uns gehört. Sonst scheitert der Start.
    private static func removeStaleSocket(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else { return false }
        return unlink(path) == 0
    }

    // MARK: Start

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
    }

    // MARK: Verbindungen (auf queue)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let status = Self.checkPeer(fd, requirement)
            guard status == errSecSuccess else {
                close(fd)
                Self.log.error("Befehlskanal: Verbindung abgelehnt (OSStatus \(status, privacy: .public))")
                continue
            }
            // Eine geprüfte neue Verbindung ersetzt die alte.
            closeClient(reason: nil)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            clientFD = fd
            buffer = Data()
            if let ack = DebugCommand.frame(["v": 1, "ok": true]) {
                _ = ack.withUnsafeBytes { write(fd, $0.baseAddress, ack.count) }
            }
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readClient() }
            src.resume()
            clientSource = src
        }
    }

    /// Audit-Token der Gegenseite → Code → Anforderung. Audit-Token statt PID: kein Wettlauf mit wiederverwendeten
    /// Prozessnummern.
    private static func checkPeer(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard status == errSecSuccess, let code else { return status == errSecSuccess ? errSecCSGuestInvalid : status }
        return SecCodeCheckValidity(code, [], requirement)
    }

    private func readClient() {
        var chunk = [UInt8](repeating: 0, count: DebugCommand.maxFrame)
        let count = read(clientFD, &chunk, chunk.count)
        if count == 0 {
            closeClient(reason: nil)
            return
        }
        if count < 0 {
            if errno != EAGAIN { closeClient(reason: "Lesefehler") }
            return
        }
        buffer.append(contentsOf: chunk[0..<count])
        while true {
            switch DebugCommand.nextFrame(&buffer) {
            case .needMore:
                return
            case .invalid:
                closeClient(reason: "ungültiger Rahmen")
                return
            case .message(let payload):
                guard let command = DebugCommand.parse(payload) else {
                    closeClient(reason: "ungültiger Befehl")
                    return
                }
                deliver(command)
            }
        }
    }

    private func closeClient(reason: String?) {
        clientSource?.cancel()
        clientSource = nil
        if clientFD >= 0 {
            close(clientFD)
            clientFD = -1
        }
        buffer = Data()
        if let reason { Self.log.notice("Befehlskanal: \(reason, privacy: .public)") }
    }

    /// Höchstens `maxPerSecond` Befehle je Sekunde; der Rest fällt weg.
    private func deliver(_ command: DebugCommand) {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1 {
            windowStart = now
            windowCount = 0
        }
        windowCount += 1
        if windowCount <= Self.maxPerSecond { onCommand(command) }
    }
}
#endif
