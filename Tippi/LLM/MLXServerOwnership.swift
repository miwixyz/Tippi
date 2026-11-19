import Foundation

// MARK: - Only Tippi's own server (audit finding 7, 2026-11-17)

/// Who owns a listener on the MLX port. Pure decisions, testable without
/// opening a socket; `MLXServerManager.start()` and `clearStaleServer` use them.
extension MLXServerManager {
    /// Whatever holds a TCP port, as `lsof` + `ps` report it.
    struct PortListener: Equatable, Sendable {
        let pid: Int32
        /// `nil` when `ps` could not tell.
        let parentPID: Int32?
        let command: String
    }

    /// Verdict on a server that *answers* on the port.
    enum AnsweringServer: Equatable {
        /// Left over from an earlier Tippi run — replace it with a fresh start.
        case leftoverOfTippi(pid: Int32)
        /// Not started by Tippi. Refused, never adopted, never killed.
        /// `pid` is `nil` when the listener could not be identified.
        case foreign(pid: Int32?, command: String)
    }

    /// Parent of a process Tippi may treat as its own leftover: `launchd` (the
    /// Tippi that started it is gone) or this very process.
    nonisolated static func isLeftoverParent(_ parentPID: Int32, ownPID: Int32) -> Bool {
        parentPID == 1 || parentPID == ownPID
    }

    /// A listener counts as Tippi's own leftover only if all of it holds:
    /// nobody else owns it (`isLeftoverParent`), and its command line is what
    /// `start()` launches — our resolved binary with `--model …`, ending in
    /// `--port <port> --host 127.0.0.1`. The model is deliberately not
    /// compared: after a crash the user may have picked another model, and the
    /// orphan would otherwise block the port as "foreign" forever.
    ///
    /// Why not "is it a Tippi child" alone: on a normal quit Tippi already stops
    /// its server (`applicationWillTerminate`), so the realistic leftover is an
    /// orphan with parent 1. Requiring our exact command line keeps a server the
    /// user runs by hand with other options out of reach. A server that is the
    /// child of another *running* program — e.g. the installed Tippi next to a
    /// test build — is foreign: same command, different owner.
    ///
    /// Known limits (review 2026-11-17): a server started by hand (`nohup`,
    /// LaunchAgent) with exactly Tippi's arguments and parent 1 counts as a
    /// leftover and is replaced. With the `uvx` install the Python listener's
    /// command line never matches, so an *answering* uvx leftover is still
    /// reported as foreign; a *silent* one is cleared via `owningParentPID`.
    nonisolated static func answeringServerVerdict(listener: PortListener?, ownPID: Int32,
                                                   binaryPath: String, port: Int) -> AnsweringServer {
        guard let listener else { return .foreign(pid: nil, command: "") }
        let command = listener.command
        guard let parent = listener.parentPID, isLeftoverParent(parent, ownPID: ownPID),
              command.contains("\(binaryPath) --model "),
              command.hasSuffix("--port \(port) --host 127.0.0.1") else {
            return .foreign(pid: listener.pid, command: command)
        }
        return .leftoverOfTippi(pid: listener.pid)
    }

    /// Short program name for a message: the `mlx_lm.server` part if present
    /// (the first word is often just `python`), else the first word.
    nonisolated static func displayName(ofCommand command: String) -> String {
        let words = command.split(separator: " ").map(String.init)
        let word = words.first { $0.contains("mlx_lm.server") } ?? words.first ?? "?"
        return (word as NSString).lastPathComponent
    }

    /// The parent that decides who owns a listener. Tippi starts the server through
    /// `uvx`/`uv` when installed that way, so the Python listener's parent is the
    /// wrapper, not Tippi. If that wrapper is itself an `mlx-lm` launcher, its own parent
    /// counts — otherwise an orphaned wrapper (parent 1) made the silent server look
    /// "foreign" and it blocked the port until ended by hand (measured 2026-11-20).
    nonisolated static func owningParentPID(parentPID: Int32?, parentCommand: String?,
                                            grandparentPID: Int32?) -> Int32? {
        guard let parentPID, let parentCommand,
              parentCommand.contains("mlx-lm") || parentCommand.contains("mlx_lm.server") else { return parentPID }
        return grandparentPID ?? parentPID
    }

    /// `ps -o ppid=,command=` for one process, or `nil`.
    nonisolated static func psLine(of pid: Int32) -> (parentPID: Int32?, command: String)? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "ppid=,command=", "-p", "\(pid)"]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        // swiftlint:disable:next optional_data_string_conversion - ersetzen statt verwerfen
        let parsed = parsePSLine(String(decoding: data, as: UTF8.self))
        return parsed.command.isEmpty ? nil : parsed
    }

    /// Splits a `ps -o ppid=,command=` line into parent PID and command.
    nonisolated static func parsePSLine(_ line: String) -> (parentPID: Int32?, command: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(of: " "), let ppid = Int32(trimmed[..<space]) else {
            return (nil, trimmed)
        }
        return (ppid, trimmed[space...].trimmingCharacters(in: .whitespaces))
    }
}
