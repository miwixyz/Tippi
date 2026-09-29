import SwiftUI

// Quick-action buttons of the prompt popup, split out of PromptPopupView.swift
// (file_length) when highlight, list, quotes and bracket pairs were added.

/// Category → accent color for the small icon badge, same idea as macOS
/// System Settings' own colored row icons — a native reference, not a
/// borrowed brand color. Kept local to the UI layer so `LocalTextAction`
/// itself (Core) never needs to import SwiftUI.
extension LocalTextActionCategory {
    var tint: Color {
        switch self {
        case .formatting: return .blue
        case .enclose: return .orange
        case .transform: return .purple
        case .info: return .teal
        }
    }
}

extension LocalTextAction {
    var isIconOnly: Bool { category == .formatting || category == .enclose }
}

/// The badge glyph: typographic label where the action has one, SF Symbol
/// otherwise. Before 2026-09-28 the popup read only `symbol`, so every
/// label-only action (AA, aa, A_b …) showed an empty coloured square.
struct LocalActionGlyph: View {
    let action: LocalTextAction
    let size: CGFloat

    var body: some View {
        if let label = action.label {
            Text(label)
                .font(.system(size: size, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Image(systemName: action.symbol)
                .font(.system(size: size, weight: .semibold))
        }
    }
}

struct LocalActionIconButton: View {
    let action: LocalTextAction
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            LocalActionGlyph(action: action, size: 13)
                .foregroundStyle(action.category.tint)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(isHovering ? 0.14 : 0.07))
        )
        .help(action.title)
        .accessibilityLabel(action.title)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

struct LocalActionButton: View {
    let action: LocalTextAction
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(action.category.tint.opacity(0.16))
                        .frame(width: 20, height: 20)
                    LocalActionGlyph(action: action, size: 10)
                        .foregroundStyle(action.category.tint)
                        .frame(width: 18)
                }
                Text(action.title)
                    .font(FamilyTheme.font(.caption))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(isHovering ? 0.14 : 0.07))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

/// Currency conversion and password generation for the hotkey popup, bundled
/// so the popup, its controller and the AppDelegate pass one value instead of
/// three parameters.
struct PopupQuickTools {
    /// Favorite currencies when the selection is an amount; empty hides the row.
    var currencyTargets: [String] = []
    /// Returns a message to show in the popup, or `nil` when done.
    var onConvert: (String) async -> String? = { _ in nil }
    var onGeneratePassword: (() -> Void)?
}

struct CurrencyTargetRow: View {
    let targets: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "€→$")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)
                .help(String(localized: "currency.convert"))
            ForEach(targets, id: \.self) { code in
                Button {
                    onSelect(code)
                } label: {
                    Text(verbatim: code)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.opacity(0.07)))
                .help(String(format: String(localized: "currency.convertTo"), code))
            }
        }
    }
}

struct PasswordButton: View {
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: "key.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.pink)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.pink.opacity(0.16)))
                Text(String(localized: "password.generate"))
                    .font(FamilyTheme.font(.caption))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(isHovering ? 0.14 : 0.07))
        )
        .onHover { isHovering = $0 }
    }
}
