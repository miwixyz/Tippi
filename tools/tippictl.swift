// tippictl — schickt der Bild-Testkopie (docs/SECURE-DESIGN-befehlskanal.md) einen Befehl und gibt ihre Antwort aus.
// Muss mit Developer ID und der Kennung dev.mwlr.tippi.ctl signiert sein, sonst lehnt die Kopie ab:
// `scripts/bild-test.sh` baut und signiert es nach build-dev/tippictl.
//
//   tippictl status
//   tippictl snapshot einstellungen|hilfe|ueber
//   tippictl appearance light|dark|system
//
// Prüft vor dem Senden, dass am Socket wirklich die signierte Bild-Testkopie lauscht.
import Darwin
import Foundation
import Security

let usage = "Nutzung: tippictl status | snapshot einstellungen|hilfe|ueber | appearance light|dark|system"
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(64) }
var message: [String: Any] = ["v": 1, "cmd": cmd]
switch (cmd, args.count) {
case ("status", 1): break
case ("snapshot", 2): message["window"] = args[1]
case ("appearance", 2): message["mode"] = args[1]
default: print(usage); exit(64)
}
let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
message["id"] = String(id)

let dir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Tippi Bild", isDirectory: true)
let serverRequirement = #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
    + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.tippi.bild" and "#
    + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

func fail(_ text: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8)); exit(code)
}

func frame(_ obj: [String: Any]) -> Data {
    let json = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    return withUnsafeBytes(of: UInt32(json.count).bigEndian) { Data($0) } + json
}

func peerPasses(_ fd: Int32) -> Bool {
    var token = audit_token_t()
    var len = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return false }
    let data = withUnsafeBytes(of: &token) { Data($0) }
    var code: SecCode?
    var req: SecRequirement?
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code) == errSecSuccess,
          let code, SecRequirementCreateWithString(serverRequirement as CFString, [], &req) == errSecSuccess, let req
    else { return false }
    return SecCodeCheckValidity(code, [], req) == errSecSuccess
}

// Verbinden
let path = dir.appendingPathComponent("debug.sock").path
var addr = sockaddr_un()
let bytes = Array(path.utf8)
guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { fail("Pfad zu lang") }
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }
let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { fail("socket fehlgeschlagen") }
var one: Int32 = 1
setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { fail("Bild-Testkopie läuft nicht (kein \(path))", 2) }
guard peerPasses(sock) else { fail("Gegenseite ist nicht die signierte Bild-Testkopie – nichts gesendet", 3) }

// Auf `ok` warten (die Kopie prüft uns genauso)
var timeout = timeval(tv_sec: 3, tv_usec: 0)
setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
var chunk = [UInt8](repeating: 0, count: 256)
let count = read(sock, &chunk, chunk.count)
guard count > 4, let ack = try? JSONSerialization.jsonObject(with: Data(chunk[4..<count])) as? [String: Any],
      ack["ok"] as? Bool == true else { fail("Kopie hat nicht bestätigt (tippictl nicht richtig signiert?)", 4) }

let out = frame(message)
_ = out.withUnsafeBytes { write(sock, $0.baseAddress, out.count) }
close(sock)

// Antwort abwarten
let answer = dir.appendingPathComponent("Antworten/\(id).json")
let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    if let data = try? Data(contentsOf: answer) {
        print(String(decoding: data, as: UTF8.self))
        try? FileManager.default.removeItem(at: answer)
        exit(0)
    }
    usleep(100_000)
}
fail("Keine Antwort nach 15 s", 5)
