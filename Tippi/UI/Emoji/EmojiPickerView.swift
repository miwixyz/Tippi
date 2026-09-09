import SwiftUI

/// Spotlight-style emoji picker: type to filter, arrows to move, Return to
/// insert. Deliberately renders nothing clever — the whole point is that it
/// appears instantly and gets out of the way.
struct EmojiPickerView: View {
    @ObservedObject var model: EmojiPickerModel
    let onPick: (Emoji) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool

    private let cellSize: CGFloat = 40
    private let gridColumns = Array(
        repeating: GridItem(.fixed(40), spacing: 4),
        count: EmojiPickerModel.columns
    )

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if model.results.isEmpty {
                emptyState
            } else {
                grid
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "emoji.search.placeholder"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                // Return is handled by the panel's key monitor so it works
                // regardless of focus; this keeps the field from beeping.
                .onSubmit { if let emoji = model.selected { onPick(emoji) } }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "emoji.search.clear"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, emoji in
                        cell(for: emoji, at: index)
                    }
                }
                .padding(8)
            }
            .frame(height: 220)
            .onChange(of: model.selectedIndex) { _, newValue in
                guard model.results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(model.results[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func cell(for emoji: Emoji, at index: Int) -> some View {
        let isSelected = index == model.selectedIndex
        return Text(emoji.character)
            .font(.system(size: 24))
            .frame(width: cellSize, height: cellSize)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { onPick(emoji) }
            .onHover { hovering in
                if hovering { model.selectedIndex = index }
            }
            .id(emoji.id)
            .help(emoji.nameDE)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(String(localized: "emoji.empty.title"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let selected = model.selected {
                Text(selected.character)
                    .font(.system(size: 15))
                Text(selected.nameDE.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.isShowingRecents {
                Text(String(localized: "emoji.footer.recents"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(String(localized: "emoji.footer.hint"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
