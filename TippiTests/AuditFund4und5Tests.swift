import ApplicationServices
import XCTest
@testable import Tippi

/// Audit 2026-11-17, Fund 4 (MLX-Kindprozesse mit fester Umgebung) und Fund 5
/// (Bedienungshilfen-Abfragen mit kurzem Zeitlimit, gescheitertes Wecken gedrosselt).
final class AuditFund4und5Tests: XCTestCase {

    // MARK: Fund 4

    func testMLXEnvironmentDropsCodeInjectionVariables() {
        let inherited = [
            "PATH": "/tmp/evil:/usr/bin",
            "PYTHONPATH": "/tmp/evil",
            "PYTHONSTARTUP": "/tmp/evil.py",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
            "HOME": "/tmp/fremd",
            "HF_HOME": "/Volumes/Modelle/hf",
            "HTTPS_PROXY": "http://proxy:8080",
            "LANG": "de_DE.UTF-8",
            "SSL_CERT_FILE": "/tmp/evil-ca.pem",
            "UV_INDEX_URL": "https://evil.example/simple",
        ]
        let env = MLXChildEnvironment.make(from: inherited, home: "/Users/test")

        XCTAssertNil(env["PYTHONPATH"])
        XCTAssertNil(env["PYTHONSTARTUP"])
        XCTAssertNil(env["DYLD_INSERT_LIBRARIES"])
        XCTAssertEqual(env["PATH"], "/Users/test/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                       "geerbter PATH wird ersetzt, nicht ergänzt")
        XCTAssertEqual(env["HOME"], "/Users/test")
        XCTAssertEqual(env["HF_HOME"], "/Volumes/Modelle/hf", "Modellort bleibt einstellbar")
        XCTAssertEqual(env["HTTPS_PROXY"], "http://proxy:8080", "Modell-Download hinter Proxy")
        XCTAssertEqual(env["LANG"], "de_DE.UTF-8")
        XCTAssertEqual(Set(env.keys), ["PATH", "HOME", "HF_HOME", "HTTPS_PROXY", "LANG"])
    }

    func testInstallerStartsProgramsWithoutAShell() {
        let direct = MLXInstaller.launch("/opt/homebrew/bin/brew", ["install", "uv"])
        XCTAssertEqual(direct.url.path, "/opt/homebrew/bin/brew")
        XCTAssertEqual(direct.arguments, ["install", "uv"])

        let bare = MLXInstaller.launch("uv", ["tool", "install", "mlx-lm"])
        XCTAssertEqual(bare.url.path, "/usr/bin/env", "Name ohne Pfad: Suche im festen PATH")
        XCTAssertEqual(bare.arguments, ["uv", "tool", "install", "mlx-lm"])
    }

    // MARK: Fund 5

    @MainActor
    func testFailedWakeIsNotRetriedOnEveryClick() {
        // Ein beendeter Prozess antwortet nie: Das Wecken scheitert (ohne Bedienungshilfen-
        // Freigabe des Testhosts ebenso) und wird erst nach `retryAfter` wiederholt.
        let pid = pid_t(Int32.max - 7)
        let start = Date()
        ChromiumAccessibility.wake(AXUIElementCreateApplication(pid), pid: pid, now: start)
        XCTAssertTrue(ChromiumAccessibility.isWaitingAfterFailure(pid: pid, now: start.addingTimeInterval(1)))
        XCTAssertFalse(ChromiumAccessibility.isWaitingAfterFailure(
            pid: pid, now: start.addingTimeInterval(ChromiumAccessibility.retryAfter + 0.1)))
    }
}
