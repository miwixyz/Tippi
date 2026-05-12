import AppKit
import SwiftUI

/// Tap-to-record control for a global key combo.
/// While recording, the next non-modifier keystroke is captured.
struct HotkeyRecorderField: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

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
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
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
            KeyComboStore.save(combo)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
