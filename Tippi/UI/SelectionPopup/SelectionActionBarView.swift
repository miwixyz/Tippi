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

    private static let iconSide: CGFloat = 30
    private static let itemSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = 10
    private static let dividerWidth: CGFloat = 1

    /// Matches the width `SelectionActionBarPanel` uses for the panel's
    /// `contentRect` — the position math runs against a known size before the
    /// panel is shown, so intrinsic sizing is not an option here.
    ///
    /// Derived from `LocalTextAction.all`, not hard-coded. The previous fixed
    /// 590 was annotated "13 local-action icons"; adding a fourteenth on
    /// 2026-09-14 clipped the translate button off the trailing edge — the
    /// second time that exact bug appeared, the earlier one being why the
    /// constant had padding added instead of being computed. Counting the
    /// actions makes the next added action correct by construction.
    /// Headroom on top of the exact arithmetic. The previous fixed constant
    /// carried the same allowance with the note that a tighter version had
    /// really clipped the trailing icon: SwiftUI's rendered button and divider
    /// widths are not exactly the numbers above. Keeping the slack means the
    /// bar is a few points wider than strictly needed and never one point too
    /// narrow — which is precisely how the 2026-09-14 clipping happened, the
    /// computed requirement being 591 against a hard-coded 590.
    private static let trailingSlack: CGFloat = 36

    static var width: CGFloat {
        let iconCount = CGFloat(LocalTextAction.all.count + 1) // + translate
        let gapCount = iconCount // one gap after each icon, incl. around the divider
        return iconCount * iconSide
            + gapCount * itemSpacing
            + dividerWidth
            + horizontalPadding * 2
            + trailingSlack
    }

    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: Self.itemSpacing) {
            ForEach(LocalTextAction.all) { action in
                Button {
                    onAction(action)
                } label: {
                    // Typographic label where the transform is about letter
                    // shapes, icon otherwise. `underscore` had no valid SF
                    // Symbol at all and rendered as an invisible button.
                    if let label = action.label {
                        Text(label)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: Self.iconSide, height: Self.iconSide)
                    } else {
                        Image(systemName: action.symbol)
                            .font(.system(size: 14))
                            .frame(width: Self.iconSide, height: Self.iconSide)
                    }
                }
                .buttonStyle(.plain)
                .help(action.title)
            }

            Divider().frame(width: Self.dividerWidth, height: 20)

            Button(action: onTranslate) {
                // Same icon Translate already uses elsewhere in Tippi
                // (Translate Quick Panel, its Help entry) — one consistent
                // symbol for "translate" across the app.
                Image(systemName: "character.bubble")
                    .font(.system(size: 14))
                    .frame(width: Self.iconSide, height: Self.iconSide)
            }
            .buttonStyle(.plain)
            .help(String(localized: "selectionPopup.translate"))
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: Self.width, height: Self.height)
        .tippiGlass(in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
