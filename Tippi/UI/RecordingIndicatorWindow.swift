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

// MARK: - Duration formatting

/// Deliberately not nested in the view: this is pure logic and belongs where a
/// unit test can reach it. `DateComponentsFormatter` was the alternative, but it
/// is locale-dependent and would render "0:07" differently per region — the pill
/// wants a stable, monospaced stopwatch, not a localized phrase.
enum RecordingDuration {
    /// m:ss below an hour, h:mm:ss beyond. Takes are short in practice, but the
    /// toggle mode has no maximum at all, so the long form has to exist.
    static func formatted(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
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
    /// Started with the mail dictation hot key: envelope instead of microphone.
    let isMail: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch mode {
            case .recording:
                Image(systemName: isMail ? "envelope.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                WaveformBars(level: recorder.level)
                Text(RecordingDuration.formatted(recorder.elapsed))
                    // Monospaced digits: without them the pill twitches on every
                    // tick as glyph widths change, and the window is sized once.
                    .font(.subheadline.weight(.medium).monospacedDigit())
                Text(String(localized: isMail ? "dictation.indicator.recordingMail" : "dictation.indicator.recording"))
                    .font(FamilyTheme.font(.subheadline, weight: .medium))
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text(aiEnabled
                     ? String(localized: "dictation.indicator.aiPolishing")
                     : String(localized: "dictation.indicator.transcribing"))
                    .font(FamilyTheme.font(.subheadline, weight: .medium))
            }
            if aiEnabled {
                aiBadge
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .tippiGlass(in: Capsule())
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
                .font(FamilyTheme.font(.subheadline, weight: .regular))
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Position (2026-10-02: six places instead of two)

extension DictationSettings {
    /// Where the recording pill (and live text) sits on the screen. The two
    /// centred cases keep their old raw values "bottom"/"top", so settings saved
    /// before 2026-10-02 carry over unchanged. Declared here, not in
    /// DictationController.swift, which is at its 750-line limit.
    enum IndicatorPosition: String, CaseIterable, Identifiable {
        case topLeft, top, topRight, bottomLeft, bottom, bottomRight
        var id: String { rawValue }

        var isTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var horizontal: HorizontalAlignment {
            switch self {
            case .topLeft, .bottomLeft: return .leading
            case .top, .bottom: return .center
            case .topRight, .bottomRight: return .trailing
            }
        }
        var alignment: Alignment { Alignment(horizontal: horizontal, vertical: isTop ? .top : .bottom) }
    }
}

// MARK: - Live text (2026-10-02)

/// Live transcription under/over the pill — only while recording, only when the
/// setting is on (LiveTranscriptionPreview). Shows the tail of the text: what is
/// being said right now. Same glass as the pill.
private struct LiveTextBox: View {
    @ObservedObject var preview: LiveTranscriptionPreview
    let size: LiveTextSize

    var body: some View {
        // The animation sits here, where `preview` is observed: on the container
        // it never fired (review 2026-10-02). Keyed on appearing only, so the
        // per-second text updates don't animate.
        ZStack { box }
            .animation(.easeOut(duration: 0.15), value: preview.text.isEmpty)
    }

    @ViewBuilder private var box: some View {
        if !preview.text.isEmpty {
            Text(LiveTranscriptionPreview.tail(preview.text, maxCharacters: size.tailCharacters))
                .font(FamilyTheme.font(size.pointSize))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                // If the text ever needs a fourth line, drop the oldest words,
                // never the ones being said right now.
                .truncationMode(.head)
                .frame(maxWidth: size.windowSize.width - 40, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .tippiGlass(in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .transition(.opacity)
                // VoiceOver reads the whole text, without the leading "…".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(preview.text))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Pill plus optional live text. With live text the window has a fixed size
/// (the text grows inside it instead of the window resizing every second); the
/// pill stays where it always was — at the bottom of that area, or at the top
/// when the indicator sits at the top of the screen.
private struct IndicatorContainer: View {
    let pill: RecordingIndicatorView
    let preview: LiveTranscriptionPreview?
    let position: DictationSettings.IndicatorPosition
    let size: LiveTextSize

    /// Transparent margin around the visible content so the drop shadow
    /// (radius 12, y 4) fits inside the window. Without it the window ended at
    /// the pill and cut the shadow into a hard-edged rectangle — measured in
    /// Michael's screenshot 2026-10-02: shadow inside the window, none below it.
    static let shadowRoom: CGFloat = 20

    var body: some View {
        content.padding(Self.shadowRoom)
    }

    @ViewBuilder private var content: some View {
        if let preview {
            VStack(alignment: position.horizontal, spacing: 8) {
                if position.isTop {
                    pill; LiveTextBox(preview: preview, size: size)
                } else {
                    LiveTextBox(preview: preview, size: size); pill
                }
            }
            .frame(width: size.windowSize.width, height: size.windowSize.height,
                   alignment: position.alignment)
        } else {
            pill
        }
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
    /// Für Tests: das Fenster der Anzeige.
    var windowForTesting: NSWindow? { window }
    /// Bumped on every show()/hide() so a pending fade-out completion from an
    /// earlier hide() can detect a newer show() interrupted it and NOT hide the
    /// freshly-shown window.
    private var generation = 0

    func show(mode: Mode, recorder: AudioRecorder, preview: LiveTranscriptionPreview? = nil,
              aiEnabled: Bool = false, providerName: String? = nil, isMail: Bool = false) {
        generation &+= 1
        let pill = RecordingIndicatorView(
            mode: mode, recorder: recorder, aiEnabled: aiEnabled, providerName: providerName, isMail: isMail)
        let live = mode == .recording ? preview : nil
        let textSize = DictationSettings.liveTextSize
        // Fixed, separately measured size — same layout-loop fix as the toast (2026-10-07).
        let (hostView, measured) = NSHostingView<AnyView>.fixedSizeHost(AnyView(IndicatorContainer(
            pill: pill, preview: live, position: DictationSettings.indicatorPosition, size: textSize)))
        let room = IndicatorContainer.shadowRoom
        let size = live == nil ? measured
            : NSSize(width: textSize.windowSize.width + 2 * room, height: textSize.windowSize.height + 2 * room)

        // On the screen that currently holds the cursor — except when the
        // indicator is already up (recording → transcribing): then it stays on
        // its screen instead of following the mouse (review 2026-10-02).
        let current = window?.isVisible == true ? window?.screen : nil
        let screen = current ?? NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Position the visible content as before; the shadow margin lies outside it.
        let content = NSSize(width: size.width - 2 * room, height: size.height - 2 * room)
        var origin = Self.origin(for: DictationSettings.indicatorPosition, size: content, in: visible)
        origin.x -= room
        origin.y -= room

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

    /// `visibleFrame` already excludes menu bar and Dock, so all edges keep
    /// fixed breathing room (80 pt top/bottom as before, 24 pt left/right)
    /// without special-casing either chrome.
    nonisolated static func origin(for position: DictationSettings.IndicatorPosition,
                                   size: NSSize, in visible: NSRect) -> NSPoint {
        let y = position.isTop ? visible.maxY - size.height - 80 : visible.minY + 80
        let x: CGFloat
        switch position.horizontal {
        case .leading: x = visible.minX + 24
        case .trailing: x = visible.maxX - size.width - 24
        default: x = visible.midX - size.width / 2
        }
        return NSPoint(x: x, y: y)
    }

    func hide() {
        generation &+= 1
        let generationAtHide = generation
        let win = window
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // concurrency-lint: on-main NSAnimationContext.runAnimationGroup delivers
            // its completion on the thread that started the group, and this one is
            // started from a @MainActor method — so the assumption holds here.
            // Unlike the UNUserNotificationCenter callback that shipped a crash in
            // 2.11.5, which runs on the framework's own queue.
            //
            // assumeIsolated lets us read the @MainActor `generation`. If a show()
            // ran during the 0.25s fade it bumped `generation` — don't order out
            // the window it just re-displayed.
            MainActor.assumeIsolated {
                guard let self, self.generation == generationAtHide else { return }
                win?.orderOut(nil)
            }
        })
    }
}
