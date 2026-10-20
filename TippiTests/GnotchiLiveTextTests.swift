import Darwin
import Security
import XCTest
@testable import Tippi

// SYNTHETIC – invented sentences, never real dictation.

/// Live text to Gnotchi 0.3.0 (Gnotchi SECURE-DESIGN G21): framing, ack, and the server check.
@MainActor
final class GnotchiLiveTextTests: XCTestCase {

    // MARK: Pure parts

    func testTailKeepsEndAtWordBoundary() {
        let text = (1...120).map { "wort\($0)" }.joined(separator: " ")
        let t = GnotchiLiveText.tail(text)
        XCTAssertTrue(t.hasPrefix("…"))
        XCTAssertTrue(t.hasSuffix("wort120"))
        XCTAssertLessThanOrEqual(t.count, GnotchiLiveText.sendChars + 1)
        XCTAssertEqual(GnotchiLiveText.tail("kurz"), "kurz")
    }

    func testFrameIsLengthPrefixedJSON() throws {
        let f = try XCTUnwrap(GnotchiLiveText.frame(text: "Hallo"))
        let len = Int(f[0]) << 24 | Int(f[1]) << 16 | Int(f[2]) << 8 | Int(f[3])
        XCTAssertEqual(len, f.count - 4)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: f.dropFirst(4)) as? [String: Any])
        XCTAssertEqual(obj["v"] as? Int, 1)
        XCTAssertEqual(obj["text"] as? String, "Hallo")
        XCTAssertLessThanOrEqual(try XCTUnwrap(GnotchiLiveText.frame(text: String(repeating: "ä", count: 5000))).count,
                                 GnotchiLiveText.maxFrame, "long text is cut, frame stays small")
    }

    func testParseAck() {
        XCTAssertEqual(GnotchiLiveText.parseAck(ack(["v": 1, "ok": true])), true)
        XCTAssertEqual(GnotchiLiveText.parseAck(ack(["v": 1, "ok": false])), false)
        XCTAssertEqual(GnotchiLiveText.parseAck(ack(["v": 2, "ok": true])), false)
        XCTAssertNil(GnotchiLiveText.parseAck(ack(["v": 1, "ok": true]).prefix(6)), "incomplete")
        XCTAssertEqual(GnotchiLiveText.parseAck(Data([0, 0, 0, 0])), false)
        XCTAssertEqual(GnotchiLiveText.parseAck(Data([0xFF, 0xFF, 0xFF, 0xFF])), false)
    }

    func testRequirementIsDeveloperIDGnotchi() throws {
        var req: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(GnotchiLiveText.requirement as CFString, [], &req), errSecSuccess)
        XCTAssertTrue(GnotchiLiveText.requirement.contains("1.2.840.113635.100.6.2.6"))
        XCTAssertTrue(GnotchiLiveText.requirement.contains(#"identifier "dev.mwlr.gnotchi""#))
    }

    // MARK: Real socket against a fake server (this test process)

    func testOpenSendsTextWhenServerPassesAndAcks() throws {
        let server = try FakeServer(reply: ack(["v": 1, "ok": true]))
        let link = try XCTUnwrap(GnotchiLiveLink.open(path: server.path, requirement: try selfRequirement()))
        link.send("Hallo Welt")
        link.close()
        let got = server.received(timeout: 2)
        XCTAssertTrue(String(bytes: got, encoding: .utf8)?.contains("Hallo Welt") == true)
    }

    func testOpenRefusesServerThatIsNotGnotchi() throws {
        let server = try FakeServer(reply: ack(["v": 1, "ok": true]))
        // Real requirement: this test process is not a Developer-ID Gnotchi → no link, nothing sent.
        XCTAssertNil(GnotchiLiveLink.open(path: server.path))
        XCTAssertTrue(server.received(timeout: 0.5).isEmpty, "no text leaves Tippi")
    }

    func testOpenFailsWithoutAckOrWithRefusal() throws {
        let silent = try FakeServer(reply: nil)
        let started = Date()
        XCTAssertNil(GnotchiLiveLink.open(path: silent.path, requirement: try selfRequirement()))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "times out quickly")
        let refusing = try FakeServer(reply: ack(["v": 1, "ok": false]))
        XCTAssertNil(GnotchiLiveLink.open(path: refusing.path, requirement: try selfRequirement()))
    }

    func testOpenFailsWithoutServer() {
        XCTAssertNil(GnotchiLiveLink.open(path: "/tmp/tippi-gnt-gibtsnicht-\(UUID().uuidString.prefix(6)).sock"))
    }

    // MARK: Helpers

    private func ack(_ obj: [String: Any]) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let n = UInt32(json.count).bigEndian
        return withUnsafeBytes(of: n) { Data($0) } + json
    }

    /// A requirement this very test process satisfies (its own designated requirement).
    private func selfRequirement() throws -> String {
        var me: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &me), errSecSuccess)
        var stat: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(me), [], &stat), errSecSuccess)
        var req: SecRequirement?
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(stat), [], &req), errSecSuccess)
        var text: CFString?
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(req), [], &text), errSecSuccess)
        return try XCTUnwrap(text) as String
    }
}

/// Listens on a short /tmp path, accepts one client, optionally answers, collects what arrives.
private final class FakeServer: @unchecked Sendable {
    let path = "/tmp/tippi-gnt-\(UUID().uuidString.prefix(6)).sock"
    private let fd: Int32
    private let lock = NSLock()
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(reply: Data?) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard r == 0, listen(fd, 1) == 0 else { throw POSIXError(.EADDRINUSE) }
        let listenFD = fd
        DispatchQueue.global().async { [self] in
            let c = accept(listenFD, nil, nil)
            guard c >= 0 else { _ = done.signal(); return }
            if let reply { _ = reply.withUnsafeBytes { write(c, $0.baseAddress, reply.count) } }
            var tv = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(c, &chunk, chunk.count)
                guard n > 0 else { break }
                lock.lock(); data.append(contentsOf: chunk[0..<n]); lock.unlock()
            }
            close(c)
            _ = done.signal()
        }
    }

    func received(timeout: TimeInterval) -> Data {
        _ = done.wait(timeout: .now() + timeout)
        lock.lock(); defer { lock.unlock() }
        return data
    }

    deinit {
        close(fd)
        unlink(path)
    }
}
