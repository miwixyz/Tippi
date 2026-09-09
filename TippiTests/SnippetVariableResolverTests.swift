import XCTest
@testable import Tippi

final class SnippetVariableResolverTests: XCTestCase {
    func testStaticReplaceWithoutVars() {
        let match = SnippetMatch(triggers: [":espanso"], replace: "Hi there!")
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "Hi there!")
    }

    func testShellVarSubstitution() {
        // printf, not `echo -n` — macOS's /bin/sh builtin echo doesn't honor
        // `-n` (POSIX sh treats it as a literal argument, not a flag), which
        // is exactly why this test caught a wrong assumption on first run.
        let match = SnippetMatch(
            triggers: [":shell"],
            replace: "{{output}}",
            vars: [SnippetVar(name: "output", type: "shell", params: SnippetVarParams(cmd: "printf hello", format: nil))]
        )
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "hello")
    }

    func testShellVarTrimsTrailingNewline() {
        let match = SnippetMatch(
            triggers: [":shell"],
            replace: "{{output}}",
            vars: [SnippetVar(name: "output", type: "shell", params: SnippetVarParams(cmd: "echo hello", format: nil))]
        )
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "hello")
    }

    func testShellVarWithInlineEnvAssignment() {
        // Real match files rely on `VAR=val cmd` working inside the `cmd:`
        // string (e.g. `LC_TIME=de_DE.UTF-8 date ...`) — verify /bin/sh -c
        // actually honors that form.
        let match = SnippetMatch(
            triggers: [":envtest"],
            replace: "{{val}}",
            vars: [SnippetVar(name: "val", type: "shell", params: SnippetVarParams(cmd: "FOO=bar sh -c 'echo $FOO'", format: nil))]
        )
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "bar")
    }

    func testMultipleVarsInOneTemplate() {
        let match = SnippetMatch(
            triggers: [":nl"],
            replace: "Kinowoche vom {{a}} bis {{b}}",
            vars: [
                SnippetVar(name: "a", type: "shell", params: SnippetVarParams(cmd: "printf '12.'", format: nil)),
                SnippetVar(name: "b", type: "shell", params: SnippetVarParams(cmd: "printf '18. Jun'", format: nil)),
            ]
        )
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "Kinowoche vom 12. bis 18. Jun")
    }

    func testDateVarProducesNonEmptyFormattedString() {
        // Can't assert an exact value (test runs on whatever date it runs),
        // but the format token must actually be honored — %Y is always
        // exactly 4 digits.
        let match = SnippetMatch(
            triggers: [":date"],
            replace: "{{mydate}}",
            vars: [SnippetVar(name: "mydate", type: "date", params: SnippetVarParams(cmd: nil, format: "%Y"))]
        )
        let result = SnippetVariableResolver.resolve(match)
        XCTAssertEqual(result.count, 4)
        XCTAssertNotNil(Int(result))
    }

    func testUnsupportedVarTypeResolvesToEmptyStringNotCrash() {
        let match = SnippetMatch(
            triggers: [":form"],
            replace: "before-{{x}}-after",
            vars: [SnippetVar(name: "x", type: "form", params: SnippetVarParams(cmd: nil, format: nil))]
        )
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "before--after")
    }

    func testEmptyShellCommandResolvesToEmptyString() {
        let match = SnippetMatch(
            triggers: [":empty"],
            replace: "{{x}}",
            vars: [SnippetVar(name: "x", type: "shell", params: SnippetVarParams(cmd: "", format: nil))]
        )
        XCTAssertEqual(SnippetVariableResolver.resolve(match), "")
    }

    /// Regression test for a real bug found in the 2026-09-09 pre-release
    /// audit: a hanging shell command used to block forever, which left
    /// `SnippetKeystrokeMonitor.isInjecting` stuck `true` and permanently
    /// disabled snippet expansion until the app restarted. Deliberately
    /// slow (waits out the real timeout) because that's exactly the
    /// behavior being verified — a command that never exits on its own
    /// must still resolve, not hang the test/app indefinitely.
    func testHangingShellCommandTimesOutInsteadOfBlockingForever() {
        let match = SnippetMatch(
            triggers: [":hang"],
            replace: "{{x}}",
            vars: [SnippetVar(name: "x", type: "shell", params: SnippetVarParams(cmd: "sleep 30", format: nil))]
        )
        let start = Date()
        let result = SnippetVariableResolver.resolve(match)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result, "", "a timed-out command has no output")
        XCTAssertLessThan(elapsed, 10, "must return well before the command's own 30s sleep — the timeout is what's being tested")
    }
}
