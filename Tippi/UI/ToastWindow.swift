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
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
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

    func show(message: String) {
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
                guard let self else { return }
                let win = self.window
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    win?.animator().alphaValue = 0
                }, completionHandler: {
                    win?.orderOut(nil)
                })
            }
        }
    }
}
