import Foundation
import Combine

// MARK: - TippiStatusMonitor

/// Aggregates Tippi's overall readiness for the menubar status badge.
///
/// "Ready" combines app-alive (always true once this runs) with the active
/// provider's readiness:
///  - Cloud provider selected → ready immediately (no local warm-up needed).
///  - MLX selected            → ready only when the local server is running AND
///                              warm (weights loaded); warming while it
///                              starts/loads; error if it failed or isn't installed.
///  - Ollama selected         → ready when the local Ollama server responds;
///                              warming while it is (still) unreachable.
///
/// A lightweight 3 s poll catches provider switches and Ollama reachability
/// without observing every UserDefaults key; MLX lifecycle changes are picked
/// up instantly via Combine.
@MainActor
final class TippiStatusMonitor: ObservableObject {
    static let shared = TippiStatusMonitor()

    /// What is wrong and what to do about it.
    ///
    /// Added 2026-09-20 after Michael's report: the menubar said only "Fehler",
    /// the actual cause sat in a settings pane nobody had open, and nothing
    /// announced it. The information already existed — `ServerState.failed`
    /// carries a message — it was simply dropped on the way up.
    ///
    /// Two fields on purpose, mirroring the vault rule for automated messages:
    /// what is going on, and a concrete instruction. A headline without an
    /// action is what produced this complaint in the first place.
    struct Problem: Equatable {
        /// Short enough for the menubar row: what is broken.
        let headline: String
        /// One sentence: the next thing to do. Shown as its own clickable menu
        /// item and as the notification body.
        let action: String
        /// Whether the fix lives in Settings, so the menu item can go there.
        var opensSettings: Bool = true
    }

    enum Status: Equatable {
        case ready     // green
        case warming   // yellow
        case error(Problem)   // red

        var isError: Bool { if case .error = self { return true }; return false }

        var problem: Problem? { if case .error(let p) = self { return p }; return nil }

        var label: String {
            switch self {
            case .ready:   return String(localized: "status.ready")
            case .warming: return String(localized: "status.warming")
            // "Fehler — MLX-Server läuft nicht" instead of a bare "Fehler".
            case .error(let p): return "\(String(localized: "status.error")) — \(p.headline)"
            }
        }
    }

    @Published private(set) var status: Status = .warming

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var ollamaReachable = false

    private init() {}

    /// Begin observing. Safe to call once from `applicationDidFinishLaunching`.
    func start() {
        MLXServerManager.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
        MLXServerManager.shared.$isWarm
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await tick() }
    }

    private func tick() async {
        if LLMRouter.shared.effectivePreferredProviderID() == "ollama" {
            ollamaReachable = await Self.pingOllama()
        }
        recompute()
    }

    private func recompute() {
        // Use the router's *effective* choice (same resolution the dictation /
        // completion path uses), not the raw UserDefaults value — they diverge
        // when the user hasn't made an explicit provider choice.
        let provider = LLMRouter.shared.effectivePreferredProviderID()
        let new: Status
        switch provider {
        case "mlx":
            if !MLXServerManager.isInstalled {
                new = .error(Problem(
                    headline: String(localized: "status.error.mlxNotInstalled"),
                    action: String(localized: "status.error.mlxNotInstalled.action")
                ))
            } else {
                switch MLXServerManager.shared.state {
                // MLX is the active provider, so a server that isn't running —
                // whether crashed (.failed) or deliberately stopped (.stopped) —
                // means Tippi can't process right now: red, not "loading" yellow.
                case .failed(let message):
                    // The manager's own message is the most specific thing
                    // anyone has (e.g. "Model download stalled at Fetching 8
                    // files 0% — check the connection and start again"). It used
                    // to be visible only in Settings; it is the action now.
                    new = .error(Problem(
                        headline: String(localized: "status.error.mlxFailed"),
                        action: message
                    ))
                case .stopped:
                    new = .error(Problem(
                        headline: String(localized: "status.error.mlxStopped"),
                        action: String(localized: "status.error.mlxStopped.action")
                    ))
                case .starting:         new = .warming   // genuinely spinning up
                case .running:          new = MLXServerManager.shared.isWarm ? .ready : .warming
                }
            }
        case "ollama":
            new = ollamaReachable ? .ready : .warming
        default:
            new = .ready   // cloud provider — instantly ready
        }
        if new != status { status = new }
    }

    /// Cheap reachability probe against the local Ollama server.
    private static func pingOllama() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
