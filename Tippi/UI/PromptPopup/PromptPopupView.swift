import SwiftUI

struct PromptPopupView: View {
    let prompts: [DemoPrompt]
    let onSelect: (DemoPrompt) -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
        }
        .frame(width: 290)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(prompts.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            onSelect(prompts[selectedIndex])
            return .handled
        }
        .onKeyPress { keyPress in
            guard let first = keyPress.characters.first,
                  let digit = Int(String(first)) else { return .ignored }
            if digit >= 1 && digit <= prompts.count {
                onSelect(prompts[digit - 1])
                return .handled
            }
            return .ignored
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline")
                .foregroundStyle(.tint)
            Text("Tippi")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                PromptRow(
                    prompt: prompt,
                    shortcut: "\(index + 1)",
                    isSelected: index == selectedIndex,
                    onHover: { selectedIndex = index },
                    onTap: { onSelect(prompt) }
                )
            }
        }
        .padding(.vertical, 6)
    }

}

private struct PromptRow: View {
    let prompt: DemoPrompt
    let shortcut: String
    let isSelected: Bool
    let onHover: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: prompt.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.white : .secondary)
                Text(prompt.title)
                    .foregroundStyle(isSelected ? Color.white : .primary)
                Spacer()
                Text(shortcut)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(isSelected ? Color.white : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
                .padding(.horizontal, 6)
        )
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}
