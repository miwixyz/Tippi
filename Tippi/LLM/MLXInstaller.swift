import Foundation

// MARK: - MLXInstaller

/// Drives one-click installation of the MLX toolchain (`uv` + `mlx-lm`) from
/// inside Tippi. The goal is to let non-technical users adopt the local MLX
/// provider without touching a Terminal.
///
/// Two-phase flow:
///   1. Install `uv` (Astral's Python tool installer) via the official installer
///      script. Skipped if `uv` is already on disk.
///   2. Run `uv tool install mlx-lm`, which downloads and registers
///      `~/.local/bin/mlx_lm.server` — exactly the path `MLXServerManager`
///      already looks for.
///
/// All output is streamed line-by-line through an `AsyncStream<Event>` so the
/// SwiftUI sheet can render a live log and final state transitions.
@MainActor
final class MLXInstaller {

    enum Event {
        case log(String)
        case phaseChanged(Phase)
        case finished(success: Bool)
    }

    enum Phase: Equatable {
        case checking
        case installingUV
        case installingMLXLM
        case done
        case failed(String)

        var displayLabel: String {
            switch self {
            case .checking:        return String(localized: "mlx.install.phase.checking")
            case .installingUV:    return String(localized: "mlx.install.phase.uv")
            case .installingMLXLM: return String(localized: "mlx.install.phase.mlxlm")
            case .done:            return String(localized: "mlx.install.phase.done")
            case .failed(let m):   return m
            }
        }
    }

    /// Run the full install pipeline. Returns a stream the UI subscribes to.
    /// The stream finishes with `.finished(success:)` and then closes.
    static func install() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached {
                continuation.yield(.phaseChanged(.checking))
                continuation.yield(.log("Checking existing installation…"))

                // Phase 1: uv
                let needsUV = await MainActor.run { !Self.isUVInstalled }
                if needsUV {
                    continuation.yield(.phaseChanged(.installingUV))
                    guard let brewPath = await MainActor.run(body: { Self.resolvedBrewPath() }) else {
                        continuation.yield(.log("✗ uv is not installed and Homebrew was not found."))
                        continuation.yield(.log("Install uv manually, then reopen this sheet: https://docs.astral.sh/uv/getting-started/installation/"))
                        continuation.yield(.phaseChanged(.failed(String(localized: "mlx.install.error.uv"))))
                        continuation.yield(.finished(success: false))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.log("Installing uv via Homebrew…"))
                    do {
                        try await runShell(
                            "\"\(brewPath)\" install uv",
                            onLine: { continuation.yield(.log($0)) }
                        )
                        continuation.yield(.log("✓ uv installed"))
                    } catch {
                        continuation.yield(.log("✗ uv installation failed: \(error.localizedDescription)"))
                        continuation.yield(.phaseChanged(.failed(String(localized: "mlx.install.error.uv"))))
                        continuation.yield(.finished(success: false))
                        continuation.finish()
                        return
                    }
                } else {
                    continuation.yield(.log("✓ uv already installed — skipping"))
                }

                // Phase 2: mlx-lm
                continuation.yield(.phaseChanged(.installingMLXLM))
                continuation.yield(.log("Installing mlx-lm via uv (this downloads PyTorch and MLX — may take a couple of minutes)…"))
                let uvPath = await MainActor.run { Self.resolvedUVPath() ?? "uv" }
                do {
                    try await runShell(
                        "\"\(uvPath)\" tool install mlx-lm",
                        onLine: { continuation.yield(.log($0)) }
                    )
                    continuation.yield(.log("✓ mlx-lm installed"))
                } catch {
                    continuation.yield(.log("✗ mlx-lm installation failed: \(error.localizedDescription)"))
                    continuation.yield(.phaseChanged(.failed(String(localized: "mlx.install.error.mlxlm"))))
                    continuation.yield(.finished(success: false))
                    continuation.finish()
                    return
                }

                // Final verification: did the binary actually land?
                let installed = await MainActor.run { MLXServerManager.isInstalled }
                if installed {
                    continuation.yield(.phaseChanged(.done))
                    continuation.yield(.finished(success: true))
                } else {
                    continuation.yield(.log("✗ Install completed but mlx_lm.server is still not on disk."))
                    continuation.yield(.phaseChanged(.failed(String(localized: "mlx.install.error.notFound"))))
                    continuation.yield(.finished(success: false))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Detection

    /// Where uv might live, in priority order.
    private static let uvCandidates: [String] = [
        "\(NSHomeDirectory())/.local/bin/uv",
        "/opt/homebrew/bin/uv",
        "/usr/local/bin/uv",
    ]

    static var isUVInstalled: Bool { resolvedUVPath() != nil }

    static func resolvedUVPath() -> String? {
        for path in uvCandidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private static let brewCandidates: [String] = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    private static func resolvedBrewPath() -> String? {
        for path in brewCandidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - Shell runner

    /// Run a shell command and stream stdout/stderr line by line.
    /// Throws if the process exits non-zero or fails to launch.
    private static func runShell(
        _ command: String,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        let runner = ShellProcessRunner()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/sh")
                proc.arguments = ["-c", command]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe

                // Ensure user's HOME and a sensible PATH are present so tools
                // installed in ~/.local/bin are reachable.
                var env = ProcessInfo.processInfo.environment
                let extraPath = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                env["PATH"] = (env["PATH"].map { "\(extraPath):\($0)" }) ?? extraPath
                env["HOME"] = NSHomeDirectory()
                proc.environment = env

                let buffer = LineBuffer()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    buffer.feed(data) { line in onLine(line) }
                }

                runner.process = proc

                do {
                    try proc.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    runner.resume(cont, throwing: error)
                    return
                }

                DispatchQueue.global(qos: .utility).async {
                    proc.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    buffer.flush { line in onLine(line) }

                    if proc.terminationStatus == 0 {
                        runner.resume(cont)
                    } else {
                        runner.resume(
                            cont,
                            throwing: NSError(
                                domain: "MLXInstaller",
                                code: Int(proc.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: "exit \(proc.terminationStatus)"]
                            )
                        )
                    }
                }
            }
        } onCancel: {
            runner.terminate()
        }
    }
}

private final class ShellProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    var process: Process?

    func terminate() {
        lock.lock()
        let proc = process
        lock.unlock()
        if proc?.isRunning == true {
            proc?.terminate()
        }
    }

    func resume(_ continuation: CheckedContinuation<Void, Error>, throwing error: Error? = nil) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

// MARK: - LineBuffer

/// Accumulates bytes from a pipe and emits complete lines.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func feed(_ data: Data, emit: (String) -> Void) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending[..<nl]
            pending.removeSubrange(...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                emit(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func flush(emit: (String) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return }
        if let line = String(data: pending, encoding: .utf8) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { emit(trimmed) }
        }
        pending.removeAll()
    }
}
