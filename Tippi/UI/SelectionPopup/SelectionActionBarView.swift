import SwiftUI

/// The PopClip-style icon row itself — every entry from `LocalTextAction.all`
/// (the same instant, no-AI transforms already available in the hotkey
/// popup's "local actions" section), just in a slim always-a-click-away bar
/// instead of buried in the full prompt popup. A separate "Translate" icon
/// follows after a divider — visually set apart because it behaves
/// differently from the rest: it opens the Translate Quick Panel with the
/// selection pre-filled instead of replacing the selection in place.
struct SelectionActionBarView: View {
    let onAction: (LocalTextAction) -> Void
    let onTranslate: () -> Void

    /// Matches the width `SelectionActionBarPanel` uses for the panel's
    /// `contentRect` — kept in sync explicitly rather than relying on
    /// intrinsic sizing, so the position math (computed against a known
    /// size before the panel is shown) never drifts from the rendered size.
    // 13 local-action icons + divider + 1 translate icon, 30pt icons with
    // 8pt spacing and 10pt padding on each side, plus headroom over the
    // tight math so icons don't clip at the trailing edge (a real bug in
    // an earlier, tighter version of this bar).
    static let width: CGFloat = 590
    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LocalTextAction.all) { action in
                Button {
                    onAction(action)
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(action.title)
            }

            Divider().frame(height: 20)

            Button(action: onTranslate) {
                // Same icon Translate already uses elsewhere in Tippi
                // (Translate Quick Panel, its Help entry) — one consistent
                // symbol for "translate" across the app.
                Image(systemName: "character.bubble")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(String(localized: "selectionPopup.translate"))
        }
        .padding(.horizontal, 10)
        .frame(width: Self.width, height: Self.height)
        .tippiGlass(in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
