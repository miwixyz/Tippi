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
    /// secure-design pass: it only ever runs for matches belonging to a file
    /// the user has explicitly approved (gated upstream in `SnippetStore`),
    /// never for an unreviewed file.
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
