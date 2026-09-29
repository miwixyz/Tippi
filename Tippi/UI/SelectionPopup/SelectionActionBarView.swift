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
    /// Length of the selection, shown right in the bar instead of behind a
    /// click (Michael, 2026-09-28). `nil` keeps the plain `#` button.
    var characterCount: Int?
    /// Target currencies when the selection is an amount (`23 €`); empty
    /// hides the conversion button.
    var currencyTargets: [String] = []
    var onConvert: (String) -> Void = { _ in }

    /// The conversion button swaps the bottom row for the favorite
    /// currencies — no menu, because a menu in this non-activating panel can
    /// take the selection with it.
    @State private var showsCurrencies = false

    private static let iconSide: CGFloat = 30
    private static let itemSpacing: CGFloat = 8
    private static let rowSpacing: CGFloat = 4
    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 7
    private static let dividerWidth: CGFloat = 1
    /// The character-count readout ("1.234" over "Zeichen") needs more room
    /// than an icon.
    private static let countWidth: CGFloat = 52

    /// Two rows instead of one (2026-09-28): with highlight, list, quotes and
    /// two more bracket pairs the single row reached ~890 pt — most of a
    /// 13-inch screen. Top row changes how text looks (format + enclose, plus
    /// Translate), bottom row changes the text itself (case, separators,
    /// counts). Split by category, so a new action lands in the right row
    /// without touching this view.
    static var topRow: [LocalTextAction] {
        LocalTextAction.all.filter { $0.category == .formatting || $0.category == .enclose }
    }

    static var bottomRow: [LocalTextAction] {
        LocalTextAction.all.filter { $0.category == .transform || $0.category == .info }
    }

    /// Matches the width `SelectionActionBarPanel` uses for the panel's
    /// `contentRect` — the position math runs against a known size before the
    /// panel is shown, so intrinsic sizing is not an option here.
    ///
    /// Derived from the action lists, not hard-coded: a fixed 590 once clipped
    /// the translate button when a fourteenth action was added (2026-09-14).
    /// Headroom on top of the exact arithmetic, because SwiftUI's rendered
    /// button and divider widths are not exactly the numbers above — a tighter
    /// version really clipped the trailing icon (591 needed, 590 given).
    private static let trailingSlack: CGFloat = 36

    private static func rowWidth(icons: Int, divider: Bool) -> CGFloat {
        let count = CGFloat(icons)
        let gaps = divider ? count : count - 1
        return count * iconSide + gaps * itemSpacing + (divider ? dividerWidth : 0)
    }

    static var width: CGFloat {
        max(rowWidth(icons: topRow.count + 1, divider: true), // + translate
            rowWidth(icons: bottomRow.count + 1, divider: false) + (countWidth - iconSide)) // + currency
            + horizontalPadding * 2
            + trailingSlack
    }

    static let height: CGFloat = iconSide * 2 + rowSpacing + verticalPadding * 2

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            HStack(spacing: Self.itemSpacing) {
                ForEach(Self.topRow) { actionButton($0) }

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
            if showsCurrencies {
                currencyRow
            } else {
                HStack(spacing: Self.itemSpacing) {
                    ForEach(Self.bottomRow) { action in
                        if action.kind == .characterCount, let characterCount {
                            countReadout(action, count: characterCount)
                        } else {
                            actionButton(action)
                        }
                    }
                    if !currencyTargets.isEmpty {
                        Button {
                            showsCurrencies = true
                        } label: {
                            Text(verbatim: "€→$")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: Self.iconSide, height: Self.iconSide)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "currency.convert"))
                    }
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.width, height: Self.height, alignment: .leading)
        .tippiGlass(in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var currencyRow: some View {
        HStack(spacing: Self.itemSpacing) {
            Button {
                showsCurrencies = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    .frame(width: Self.iconSide, height: Self.iconSide)
            }
            .buttonStyle(.plain)
            .help(String(localized: "currency.back"))

            ForEach(currencyTargets, id: \.self) { code in
                Button {
                    onConvert(code)
                } label: {
                    Text(verbatim: code)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(height: Self.iconSide)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(String(format: String(localized: "currency.convertTo"), code))
            }
        }
    }

    private func countReadout(_ action: LocalTextAction, count: Int) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(spacing: 0) {
                Text(count.formatted())
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(action.title)
                    .font(FamilyTheme.font(8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: Self.countWidth, height: Self.iconSide)
        }
        .buttonStyle(.plain)
        .help(String(format: String(localized: "local.action.characterCount.result"), count))
    }

    private func actionButton(_ action: LocalTextAction) -> some View {
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
}
