import AppKit
import SwiftUI

/// Single owner of the local key monitor used by every recorder field.
///
/// `NSEvent` monitors dispatch LIFO, and `TabView` mounts all tabs eagerly — so a
/// recorder on an invisible tab can still hold the monitor and swallow keystrokes
/// meant for the visible one. Both recorder types therefore share one slot rather
/// than keeping separate ones that cannot see each other.
///
/// Removal is idempotent on purpose: calling `NSEvent.removeMonitor` twice on the
/// same token over-releases it and crashes (seen 2026-06-03 and 2026-06-10).
enum RecorderMonitorStore {
    static var active: Any?

    static func release() {
        if let active { NSEvent.removeMonitor(active) }
        active = nil
    }
}

/// Tap-to-record control for a single modifier key.
///
/// Deliberately a recorder, not a menu. A menu of eight names ("Left Control",
/// "Right Option", …) asks the user to know which key under their fingers carries
/// which label — and on 2026-09-10 that failed in exactly the predictable way:
/// the setting read Left Control while the key being pressed was left Command.
/// Pressing the key cannot be wrong in that way, and it survives remapped
/// keyboards, which a hardcoded list never would.
struct ModifierRecorderField: View {
    @Binding var modifier: ModifierKey
    @State private var recording = false
    @State private var monitor: Any?
    /// Set when a non-modifier key was pressed, so the field can say why nothing
    /// happened instead of appearing to ignore the user.
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    Image(systemName: recording ? "record.circle.fill" : "keyboard")
                        .foregroundStyle(recording ? Color.red : Color.secondary)
                    Text(recording
                         ? String(localized: "modifier.recorder.pressNow")
                         : modifier.displayName)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(recording
                         ? String(localized: "hotkey.recorder.cancelHint")
                         : String(localized: "hotkey.recorder.changeHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording ? Color.accentColor : Color.secondary.opacity(0.35),
                                lineWidth: recording ? 2 : 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if rejected {
                Text(String(localized: "modifier.recorder.needsModifier"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        RecorderMonitorStore.release()
        recording = true
        rejected = false

        let installed = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape cancels
                    stopRecording()
                    return nil
                }
                // A normal key cannot drive this gesture: the tap must see press
                // AND release, which only modifiers report via flagsChanged.
                rejected = true
                return nil
            }

            guard let pressed = ModifierKey.from(keyCode: event.keyCode) else {
                return nil
            }
            // Only react to the press, never the release — otherwise letting go
            // of the key would immediately re-trigger and close the recorder
            // before the user sees what was captured.
            guard isDown(pressed, in: event.modifierFlags) else { return nil }

            modifier = pressed
            // Persisting is the caller's job, via .onChange on the binding.
            stopRecording()
            return nil
        }
        monitor = installed
        RecorderMonitorStore.active = installed
    }

    /// `modifierFlags` carries no left/right distinction, so this only answers
    /// "is a key of this group currently down" — which is all that separates a
    /// press from a release for the key we already identified by keycode.
    private func isDown(_ key: ModifierKey, in flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .leftShift, .rightShift:     return flags.contains(.shift)
        case .leftControl, .rightControl: return flags.contains(.control)
        case .leftOption, .rightOption:   return flags.contains(.option)
        case .leftCommand, .rightCommand: return flags.contains(.command)
        }
    }

    private func stopRecording() {
        if let monitor,
           let active = RecorderMonitorStore.active,
           (monitor as AnyObject) === (active as AnyObject) {
            RecorderMonitorStore.release()
        }
        monitor = nil
        recording = false
    }
}
