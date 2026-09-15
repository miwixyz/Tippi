import Darwin
import Foundation
import os

private let resolverLog = Logger(subsystem: "com.tippi.app", category: "snippet-resolve")

/// Executes a match's `vars` and substitutes `{{name}}` placeholders in
/// `replace`. Only `shell` and `date` are implemented — the only two types
/// that appear in any real match file. An unsupported type resolves to an
/// empty string and logs, rather than throwing: a snippet expansion happens
/// mid-typing, and a broken one variable must produce a bad expansion, never
/// crash the keystroke path for everything else.
enum SnippetVariableResolver {
    static func resolve(_ match: SnippetMatch) -> String {
        var resolved = match.replace
        for variable in match.vars {
            let value = resolveValue(variable)
            resolved = resolved.replacingOccurrences(of: "{{\(variable.name)}}", with: value)
        }
        return resolved
    }

    private static func resolveValue(_ variable: SnippetVar) -> String {
        switch variable.type {
        case "shell":
            return runShell(variable.params.cmd ?? "")
        case "date":
            return formatDate(variable.params.format ?? "%Y-%m-%d")
        default:
            resolverLog.notice("snippet var '\(variable.name, privacy: .public)': unsupported type '\(variable.type, privacy: .public)' — resolving to empty string")
            return ""
        }
    }

    /// Runs `cmd` via `/bin/sh -c` — a full command line, not an argv array,
    /// matching Espanso's own semantics (inline env assignments like
    /// `LC_TIME=de_DE.UTF-8 date ...` only work that way). This is exactly
    /// the arbitrary-shell-execution surface flagged in the feature's
    /// secure-design pass. Two separate gates upstream in `SnippetStore` decide
    /// whether a command ever reaches here, and which one applies depends on
    /// where the snippet came from: an imported snippet needs a per-snippet
    /// approval signed with the Keychain key (`SnippetApprovalSigner.verify`),
    /// an app-created one has to be a command the builder itself could have
    /// emitted (`DynamicVariableBuilder.canGenerate`). The whole-file approval
    /// this comment used to describe no longer exists — files in the watched
    /// directory are not executed in place at all, they have to be imported.
    /// Hard ceiling on how long a snippet's shell var may run. Real bug
    /// found in the 2026-09-09 pre-release audit: `waitUntilExit()` used to
    /// have no timeout at all — a command that hangs (blocked on stdin, an
    /// unreachable network call with no timeout flag, an infinite loop)
    /// never returned, which never reset `SnippetKeystrokeMonitor.isInjecting`
    /// back to `false`, which permanently disabled snippet expansion until
    /// the app was restarted. 5s is generous for what these commands
    /// actually do (format today's date, one `date -v` call) — nothing
    /// legitimate here should ever approach it.
    private static let shellTimeoutSeconds: TimeInterval = 5

    private static func runShell(_ cmd: String) -> String {
        guard !cmd.isEmpty else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        // Fixed environment instead of inheriting the app's.
        //
        // Every gate upstream — the generated-command allow-list in
        // `DynamicVariableBuilder`, the per-snippet HMAC in
        // `SnippetApprovalSigner`, the file-content hash for referenced files —
        // authorises a *command string*. None of them authorises a *binary*.
        // With an inherited PATH, `date` is whatever PATH resolves it to, so a
        // writable directory placed ahead of /usr/bin turns an approved,
        // unchanged snippet into arbitrary code execution. Measured in the
        // 2026-09-15 audit: `launchctl setenv PATH …` needs no admin rights and
        // no TCC prompt, and a GUI app launched afterwards inherits it.
        //
        // Pinning PATH to the system directories makes the allow-list mean what
        // it appears to mean. HOME stays because `date` and friends read it;
        // nothing else is passed through.
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
        ]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe() // discard stderr — must never leak into the expanded text

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            resolverLog.error("snippet shell var failed to launch: \(error.localizedDescription, privacy: .public)")
            return ""
        }

        if exited.wait(timeout: .now() + shellTimeoutSeconds) == .timedOut {
            resolverLog.error("snippet shell var timed out after \(shellTimeoutSeconds, privacy: .public)s, killing: \(cmd, privacy: .public)")
            process.terminate()
            _ = exited.wait(timeout: .now() + 1) // let it die cleanly before reading the pipe
            return ""
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .newlines)
    }

    /// `format` uses Espanso's strftime-style tokens (`%m/%d/%Y`, `%B`, `%V`,
    /// …) — the same tokens the `date`/`strftime` shell command understands.
    /// Calling the C `strftime` directly avoids hand-mapping to
    /// `DateFormatter`'s unrelated token set (which uses `MM/dd/yyyy` etc.).
    private static func formatDate(_ format: String) -> String {
        var t = time_t(Date().timeIntervalSince1970)
        var tmStruct = tm()
        localtime_r(&t, &tmStruct)
        var buffer = [Int8](repeating: 0, count: 256)
        let count = format.withCString { formatCStr in
            strftime(&buffer, buffer.count, formatCStr, &tmStruct)
        }
        guard count > 0 else { return "" }
        return String(cString: buffer)
    }
}
