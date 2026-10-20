import Darwin
import Foundation
import Security

/// Live-preview text in Gnotchi's notch island (from Gnotchi 0.3.0; Gnotchi SECURE-DESIGN G21).
///
/// Dictated text is as private as the microphone, so it never goes over the public
/// `DistributedNotificationCenter` (G17). Instead: a local Unix socket that Gnotchi owns in
/// `~/Library/Application Support/Gnotchi/live.sock`. Before a single byte of text leaves Tippi, the
/// process at the other end is checked via its audit token against a **Developer ID** requirement for
/// `dev.mwlr.gnotchi` (team LTKJ6Z2VYB). Gnotchi checks Tippi the same way and answers `ok`. Any failure →
/// Tippi keeps its own pill, exactly as before. Text is never logged.
enum GnotchiLiveText {

    static let maxFrame = 4096
    /// Only the end of the text goes out; Gnotchi shows about two lines.
    static let sendChars = 300
    /// How long to wait for Gnotchi's `ok` at dictation start (local socket: normally a few ms).
    static let ackTimeout: TimeInterval = 0.2

    /// Developer ID only – an Apple Development build carries `get-task-allow` and could be attached to.
    static let requirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.gnotchi" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    static var socketPath: String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Gnotchi/live.sock").path
    }

    enum IndicatorMode: Equatable { case tippiPill, gnotchi, gnotchiLive }

    /// Without live preview Gnotchi shows the state (0.2.0). With live preview only if the text link is up –
    /// otherwise Tippi's pill, because Gnotchi alone would show no text.
    static func indicatorMode(livePreview: Bool, gnotchiReady: Bool, liveLinkReady: Bool) -> IndicatorMode {
        guard gnotchiReady else { return .tippiPill }
        guard livePreview else { return .gnotchi }
        return liveLinkReady ? .gnotchiLive : .tippiPill
    }

    // MARK: Pure parts (tested)

    /// The end of the text at a word boundary, with "…" in front.
    static func tail(_ text: String, limit: Int = sendChars) -> String {
        guard text.count > limit else { return text }
        var cut = String(text.suffix(limit))
        if let space = cut.prefix(max(limit / 10, 8)).firstIndex(of: " ") {
            cut = String(cut[cut.index(after: space)...])
        }
        return "…" + cut
    }

    /// 4-byte big-endian length + JSON `{"v":1,"text":"…"}`.
    static func frame(text: String) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: ["v": 1, "text": tail(text)]),
              json.count + 4 <= maxFrame else { return nil }
        let n = UInt32(json.count).bigEndian
        return withUnsafeBytes(of: n) { Data($0) } + json
    }

    /// `true` when `buffer` holds Gnotchi's complete `{"v":1,"ok":true}` frame, `false` for anything
    /// else that is complete, `nil` while incomplete.
    static func parseAck(_ buffer: Data) -> Bool? {
        guard buffer.count >= 4 else { return nil }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length + 4 <= maxFrame else { return false }
        guard buffer.count >= length + 4 else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: buffer.dropFirst(4).prefix(length)) as? [String: Any],
              (obj["v"] as? NSNumber)?.intValue == 1 else { return false }
        return (obj["ok"] as? Bool) == true
    }
}

/// One verified connection per dictation. Main actor only (owned by `DictationIndicator`).
@MainActor
final class GnotchiLiveLink {
    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    /// Connect, verify the server process, wait for `ok`. `nil` on any failure (no Gnotchi 0.3.0 running,
    /// foreign process at the path, Gnotchi refused us, timeout).
    static func open(path: String? = GnotchiLiveText.socketPath,
                     requirement: String = GnotchiLiveText.requirement) -> GnotchiLiveLink? {
        guard let path else { return nil }
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) } }
        guard connected == 0, serverPasses(fd, requirement), readAck(fd) else {
            Darwin.close(fd)
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return GnotchiLiveLink(fd: fd)
    }

    /// Audit token of the listening process → code → requirement (audit token, not PID: no reuse race).
    private static func serverPasses(_ fd: Int32, _ requirement: String) -> Bool {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return false }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    private static func readAck(_ fd: Int32) -> Bool {
        let usec = Int32(GnotchiLiveText.ackTimeout * 1_000_000)
        var tv = timeval(tv_sec: 0, tv_usec: usec)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return false }   // closed (Gnotchi refused us) or timeout
            buffer.append(contentsOf: chunk[0..<n])
            if let ok = GnotchiLiveText.parseAck(buffer) { return ok }
        }
    }

    /// Non-blocking. If the socket buffer is full the update is dropped – the next one carries the whole
    /// text again. Any other error closes the link (Gnotchi quit).
    func send(_ text: String) {
        guard fd >= 0, !text.isEmpty, let data = GnotchiLiveText.frame(text: text) else { return }
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        if n < 0, errno == EAGAIN { return }
        // Error, or a partial frame – the stream would be out of step, so end it cleanly.
        if n != data.count { close() }
    }

    func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }
}
