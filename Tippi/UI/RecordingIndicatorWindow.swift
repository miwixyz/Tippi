import AppKit
import SwiftUI

// MARK: - Indicator view

private struct RecordingIndicatorView: View {
    let mode: RecordingIndicatorWindowController.Mode
    @SwiftUI.State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            switch mode {
            case .recording:
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.0 : 0.6)
                    .opacity(pulse ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                Text(String(localized: "dictation.indicator.recording"))
                    .font(.subheadline.weight(.medium))
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "dictation.indicator.transcribing"))
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

// MARK: - Controller

/// Persistent floating indicator for dictation. Unlike the toast, it stays
/// visible until `hide()` is called. Non-activating and mouse-transparent so
/// it never steals focus from the app being dictated into.
@MainActor
final class RecordingIndicatorWindowController {
    static let shared = RecordingIndicatorWindowController()
    private init() {}

    enum Mode { case recording, transcribing }

    private var window: NSWindow?

    func show(mode: Mode) {
        let hostView = NSHostingView(rootView: RecordingIndicatorView(mode: mode))
        hostView.layout()
        let size = hostView.fittingSize

        // Bottom-center of the screen that currently holds the cursor.
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 80
        )

        if let w = window {
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
    }

    func hide() {
        let win = window
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win?.animator().alphaValue = 0
        }, completionHandler: {
            win?.orderOut(nil)
        })
    }
}
