import AppKit
import SwiftUI

// MARK: - Waveform bars

private struct WaveformBars: View {
    let level: Float
    private let barCount = 8

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.easeInOut(duration: 0.12), value: level)
            }
        }
        .frame(height: 20, alignment: .center)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 3
        let range: CGFloat = 15
        // Sine envelope: center bars taller, edges shorter for a natural look
        let phase = CGFloat(index) / CGFloat(barCount - 1)
        let envelope = sin(phase * .pi)
        // Alternate bars nudge slightly for visual texture
        let nudge: CGFloat = index.isMultiple(of: 2) ? 0 : CGFloat(level) * 2
        return base + CGFloat(level) * range * (0.4 + 0.6 * envelope) + nudge
    }
}

// MARK: - Indicator view

private struct RecordingIndicatorView: View {
    let mode: RecordingIndicatorWindowController.Mode
    @ObservedObject var recorder: AudioRecorder
    let aiEnabled: Bool
    /// Display name of the AI provider handling cleanup (e.g. "Groq", "Claude").
    /// nil = generic AI badge. Shown only when aiEnabled is true.
    let providerName: String?

    var body: some View {
        HStack(spacing: 8) {
            switch mode {
            case .recording:
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                WaveformBars(level: recorder.level)
                Text(String(localized: "dictation.indicator.recording"))
                    .font(.subheadline.weight(.medium))
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text(aiEnabled
                     ? String(localized: "dictation.indicator.aiPolishing")
                     : String(localized: "dictation.indicator.transcribing"))
                    .font(.subheadline.weight(.medium))
            }
            if aiEnabled {
                aiBadge
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    /// Status hint (not a button) — the whole window ignores mouse events.
    /// When `providerName` is known (cleanup step), shows the actual provider
    /// (e.g. "· ✨ Groq"). During transcription (provider not yet known),
    /// falls back to the generic "· ✨ KI" label.
    private var aiBadge: some View {
        HStack(spacing: 4) {
            Text("·")
                .foregroundStyle(.tertiary)
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .regular))
            Text(providerName ?? String(localized: "dictation.indicator.aiSuffix"))
                .font(.subheadline.weight(.regular))
        }
        .foregroundStyle(.secondary)
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
    /// Bumped on every show()/hide() so a pending fade-out completion from an
    /// earlier hide() can detect a newer show() interrupted it and NOT hide the
    /// freshly-shown window.
    private var generation = 0

    func show(mode: Mode, recorder: AudioRecorder, aiEnabled: Bool = false, providerName: String? = nil) {
        generation &+= 1
        let hostView = NSHostingView(rootView: RecordingIndicatorView(mode: mode, recorder: recorder, aiEnabled: aiEnabled, providerName: providerName))
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
        generation &+= 1
        let generationAtHide = generation
        let win = window
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Completion fires on the main thread; assumeIsolated lets us read the
            // @MainActor `generation`. If a show() ran during the 0.25s fade it
            // bumped `generation` — don't order out the window it just re-displayed.
            MainActor.assumeIsolated {
                guard let self, self.generation == generationAtHide else { return }
                win?.orderOut(nil)
            }
        })
    }
}
