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

    enum Status: Equatable {
        case ready     // green
        case warming   // yellow
        case error     // red

        var label: String {
            switch self {
            case .ready:   return String(localized: "status.ready")
            case .warming: return String(localized: "status.warming")
            case .error:   return String(localized: "status.error")
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
                new = .error
            } else {
                switch MLXServerManager.shared.state {
                // MLX is the active provider, so a server that isn't running —
                // whether crashed (.failed) or deliberately stopped (.stopped) —
                // means Tippi can't process right now: red, not "loading" yellow.
                case .failed, .stopped: new = .error
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
