import AppKit
import SwiftUI

// MARK: - Toast view

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 13, weight: .medium))
                .symbolEffect(.bounce)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .tippiGlass(in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

// MARK: - Controller

/// Lightweight floating toast. Call `ToastWindowController.shared.show(message:)`.
/// - Appears just below the cursor, auto-dismisses after 1.5 s with a 0.3 s fade.
/// - Non-activating, mouse-transparent — the user's workflow is never interrupted.
@MainActor
final class ToastWindowController {
    static let shared = ToastWindowController()
    private init() {}

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?
    /// Bumped on every `show()`. A dismiss sequence scheduled by an older
    /// call checks this before it's allowed to touch the window — real bug,
    /// reported 2026-09-13 ("manchmal bleibt diese Pill hängen"): once an old
    /// dismiss's 1.5s sleep elapses and it starts its `NSAnimationContext`
    /// fade, `dismissTask?.cancel()` below can no longer stop it — Task
    /// cancellation only affects code that hasn't executed past its next
    /// cancellation check yet, not an animation block already in flight. The
    /// old fade (and its `orderOut` completion) then races a newer toast that
    /// reused the same window, clobbering or hiding its fresh content.
    private var generation = 0

    func show(message: String) {
        generation += 1
        let myGeneration = generation
        // Cancel any in-flight dismiss so rapid consecutive toasts don't flicker.
        dismissTask?.cancel()

        // Size the content via a temporary hosting view.
        let hostView = NSHostingView(rootView: ToastView(message: message))
        hostView.layout()
        let size = hostView.fittingSize

        // Position just below the cursor with a small gap.
        let cursor = NSEvent.mouseLocation
        let origin = NSPoint(
            x: cursor.x - size.width / 2,
            y: cursor.y - size.height - 14
        )

        if let w = window {
            // Reuse existing window — swap content & reposition.
            w.contentView = hostView
            w.setFrame(NSRect(origin: origin, size: size), display: true)
            w.alphaValue = 1.0
            w.orderFront(nil)
        } else {
            let w = NSWindow(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [],
                backing: .buffered,
                defer: false
            )
            w.contentView = hostView
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.orderFront(nil)
            window = w
        }

        // Auto-dismiss after 1.5 s, then fade out over 0.3 s.
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == myGeneration else { return }
                let win = self.window
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    win?.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == myGeneration else { return }
                        win?.orderOut(nil)
                    }
                })
            }

            // Safety net: still reported stuck ("bleibt manchmal hängen",
            // 2026-09-13) even after the generation-counter fix above closed
            // the overlapping-dismiss race. `NSAnimationContext`'s completion
            // handler is not guaranteed to fire in every situation — e.g. the
            // display sleeping mid-fade — leaving the window sitting at a
            // partial or full alpha with nothing left to ever call
            // `orderOut`. Forces it hidden after a hard deadline regardless
            // of whether the animation's own completion handler already did
            // — idempotent (hiding an already-hidden window is a no-op), and
            // still generation-guarded so it can't hide a *newer* toast.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == myGeneration else { return }
                self.window?.orderOut(nil)
            }
        }
    }
}
