import Foundation

// MARK: - AI Activity Monitor

/// Tracks in-flight LLM requests app-wide. Any component that fires an AI call
/// calls `begin()` before the request and `end()` (or relies on the automatic
/// defer in LLMRouter) when it finishes or throws.
///
/// Observers (e.g. AppDelegate for the menubar animation) subscribe to
/// `$isActive` and react accordingly. The counter is reference-counted so
/// concurrent requests (popup + dictation cleanup) are handled correctly.
@MainActor
final class AIActivityMonitor: ObservableObject {
    static let shared = AIActivityMonitor()
    private init() {}

    @Published private(set) var isActive = false

    private var count = 0

    func begin() {
        count += 1
        isActive = true
    }

    func end() {
        count = max(0, count - 1)
        isActive = count > 0
    }
}
