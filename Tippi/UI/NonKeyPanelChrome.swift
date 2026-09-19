import AppKit
import SwiftUI

/// Shared chrome for Tippi's **non-key** floating panels: the selection action
/// bar and the `:prefix` emoji suggestion list.
///
/// Both types below existed twice — once in `SelectionActionBarPanel`, once in
/// `EmojiSuggestionPanel` — and drifted apart exactly the way duplicated
/// chrome does: the glass-transparency fix of 2026-09-14 landed in one copy
/// only, so the suggestion list kept rendering as a flat light slab while the
/// action bar turned to glass. Found by audit 2026-09-19, same class of finding
/// as the threefold replacement ladder (see `ReplacementTarget`).
///
/// Panels that DO need key status (`TranslateQuickPanel`,
/// `PromptPopupController`, `PreviewWindowController`, `EmojiPickerPanel`) are
/// deliberately not covered here — they have text fields and override
/// `canBecomeKey` to `true`, which is the opposite requirement.

/// Non-activating, non-key floating panel.
///
/// Deliberately NOT the `NonActivatingKeyPanel` pattern `TranslateQuickPanel`/
/// `PromptPopupController` use — those panels have a text field the user types
/// into, so THEY genuinely need key-window status to receive keystrokes. A bar
/// of mouse-click buttons with no text input does not, and becoming key was a
/// real showstopper bug (found 2026-09-09): on macOS there is exactly one key
/// window system-wide, so once such a panel became key, ⌘C/⌘V/⌘X/Delete/typing
/// and even Escape all stopped reaching the app the user was actually working
/// in — every one of those keystrokes was silently swallowed by a panel that
/// has no text field to do anything with them.
///
/// `canBecomeKey` is explicitly `false`. Buttons still respond to the very
/// first click without it: `ClickableHostingView.acceptsFirstMouse` tells
/// AppKit the view accepts clicks even while its window isn't key, which is
/// the standard, narrower mechanism background utility panels use instead of
/// grabbing key status wholesale.
final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// `NSHostingView` doesn't accept clicks in a non-key window by default —
/// this override is the whole reason a panel can stay non-key and still be
/// clickable.
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// `glassEffect` can only sample what is behind it. The panel itself is
    /// already `isOpaque = false` with a clear background, but the hosting
    /// view in between kept its own opaque backing layer, so the surface
    /// rendered as a flat light slab instead of glass (reported 2026-09-14).
    /// Making this view transparent too completes the chain from the glass
    /// material down to the screen behind the window.
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}
