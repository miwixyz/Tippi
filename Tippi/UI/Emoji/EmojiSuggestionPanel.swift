import AppKit
import SwiftUI

/// Passive suggestion list shown next to the caret while the user types
/// `:something`, Slack/Rocket style.
///
/// `canBecomeKey` is `false`, and that is the whole design constraint. The user
/// is typing into *another* app — this panel must never take keyboard focus, or
/// their keystrokes would stop reaching the app they're writing in (exactly the
/// v2.0.1 showstopper). It therefore has no keyboard navigation at all:
/// selection happens by continuing to type, by Tab/Space (handled upstream in
/// the keystroke monitor, which can retract the character afterwards), or by
/// clicking. Arrow keys and Return belong to the target app and stay there.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the very first click without the window needing
/// key status — same trick as `SelectionActionBarPanel`.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class EmojiSuggestionPanel {
    /// Keep the list short: it sits on top of the user's document, and a long
    /// list is both visually intrusive and slower to scan than just typing
    /// another letter.
    static let maxSuggestions = 6

    private var panel: NSPanel?
    private var model = EmojiSuggestionModel()
    private var onPick: ((Emoji) -> Void)?

    var isOpen: Bool { panel != nil }

    /// Currently highlighted entry — what Tab/Space will insert.
    var topSuggestion: Emoji? { model.suggestions.first }

    /// Shows or updates the list. `anchor` is the caret rect in AppKit screen
    /// coordinates; nil falls back to the mouse location, the same fallback
    /// the selection action bar uses when an app doesn't implement
    /// bounds-for-range.
    func show(suggestions: [Emoji], anchor: CGRect?, onPick: @escaping (Emoji) -> Void) {
        guard !suggestions.isEmpty else {
            close()
            return
        }
        self.onPick = onPick
        model.suggestions = suggestions

        if panel == nil {
            createPanel()
            // Position only when first opening. The caret moves a few pixels
            // per character, but re-querying Accessibility on every keystroke
            // would put a synchronous cross-process call in the typing path —
            // and a list that creeps sideways as you type reads as jitter.
            positionPanel(anchor: anchor)
        }
        panel?.orderFront(nil)
    }

    private func createPanel() {
        let view = EmojiSuggestionView(model: model) { [weak self] emoji in
            self?.onPick?(emoji)
        }
        let hosting = ClickableHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]

        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        self.panel = panel
    }

    private func positionPanel(anchor: CGRect?) {
        guard let panel else { return }
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 260, height: 40)
        panel.setContentSize(size)

        let gap: CGFloat = 6
        let point: NSPoint
        if let anchor {
            // Below the caret line by default.
            point = NSPoint(x: anchor.minX, y: anchor.minY - size.height - gap)
        } else {
            let mouse = NSEvent.mouseLocation
            point = NSPoint(x: mouse.x, y: mouse.y - size.height - gap)
        }

        // Keep it fully on the screen the anchor is on.
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var x = min(max(point.x, visible.minX + 4), visible.maxX - size.width - 4)
        var y = point.y
        if y < visible.minY + 4 {
            // No room below — flip above the caret instead of hanging off-screen.
            y = (anchor?.maxY ?? NSEvent.mouseLocation.y) + gap
        }
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        onPick = nil
        model.suggestions = []
    }
}

/// Separate object so the panel can push new suggestions into a live view
/// without rebuilding the window on every keystroke.
@MainActor
final class EmojiSuggestionModel: ObservableObject {
    @Published var suggestions: [Emoji] = []
}

private struct EmojiSuggestionView: View {
    @ObservedObject var model: EmojiSuggestionModel
    let onPick: (Emoji) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, emoji in
                row(for: emoji, isTop: index == 0)
            }
        }
        .padding(4)
        .frame(width: 260, alignment: .leading)
        .tippiGlass(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func row(for emoji: Emoji, isTop: Bool) -> some View {
        HStack(spacing: 8) {
            Text(emoji.character)
                .font(.system(size: 17))
            Text(emoji.nameDE.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 12))
                .foregroundStyle(isTop ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isTop {
                // Names the key that inserts it — without this the list looks
                // like it wants arrow keys, which deliberately don't work here.
                Text("⇥")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isTop ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onPick(emoji) }
    }
}
