import AppKit
import SwiftUI

/// Tap-to-record control for a global key combo.
/// While recording, the next non-modifier keystroke is captured.
struct HotkeyRecorderField: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    /// Cleanup closure of whichever recorder most-recently started recording.
    /// SwiftUI `TabView` mounts all tabs eagerly, so an invisible-tab recorder
    /// from a previous interaction can still own the local key monitor and
    /// swallow keystrokes meant for the currently-visible recorder
    /// (NSEvent monitors dispatch LIFO). The next `startRecording()` calls
    /// this before installing its own monitor, forcing the prior recorder
    /// to release. Discovered 2026-06-03 during dictation-hotkey debug.
    private static var releasePrior: (() -> Void)?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 8) {
                Image(systemName: recording ? "record.circle.fill" : "keyboard")
                    .foregroundStyle(recording ? Color.red : Color.secondary)
                Text(recording
                     ? String(localized: "hotkey.recorder.pressNow")
                     : combo.displayString)
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
                    .stroke(
                        recording ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: recording ? 2 : 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(recording ? Color.accentColor.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        // Force any other recorder (e.g. from an eager-mounted invisible tab)
        // to release its local key monitor first — otherwise its LIFO-priority
        // callback would swallow our keystroke.
        Self.releasePrior?()

        recording = true
        let installed = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let mods = event.modifierFlags.intersection(relevant)
            if event.keyCode == 53 { // Escape — cancel recording
                stopRecording()
                return nil
            }
            guard !mods.isEmpty else {
                return event
            }
            combo = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            // Persistence is the caller's responsibility, propagated via the
            // parent's `.onChange(of: combo)` handler. Hardcoding any specific
            // store here would silently overwrite it whenever this field is
            // bound to a different store (e.g. dictation vs. prompt).
            stopRecording()
            return nil
        }
        monitor = installed
        Self.releasePrior = { NSEvent.removeMonitor(installed) }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        // Leave Self.releasePrior alone — another instance may have replaced
        // it. A second removeMonitor() call against an invalid token is a
        // harmless no-op, so we don't need closure-identity tracking here.
    }
}
