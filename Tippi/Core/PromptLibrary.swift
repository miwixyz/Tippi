import Foundation

// MARK: - Edits to built-in prompts

/// The user's changes to one built-in prompt. A `nil` field keeps the original,
/// so an untouched title stays localized (German Mac shows German, English Mac
/// English) and only what was actually changed is stored — and synced.
struct BuiltInPromptEdit: Codable, Equatable {
    var title: String?
    var symbol: String?
    var systemPrompt: String?
    /// Only meaningful for the built-in chain; a single-step prompt stays single.
    var pipeline: [String]?

    var isEmpty: Bool { title == nil && symbol == nil && systemPrompt == nil && pipeline == nil }

    /// Records only the fields that differ from `original` (the unedited built-in).
    /// Compared trimmed, because the editor trims what it saves.
    init(original: DemoPrompt, title: String, symbol: String, systemPrompt: String, pipeline: [String]?) {
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.title = title == trimmed(original.title) ? nil : title
        self.symbol = symbol == original.symbol ? nil : symbol
        self.systemPrompt = systemPrompt == trimmed(original.instructions) ? nil : systemPrompt
        self.pipeline = (pipeline ?? []) == (original.pipeline ?? []) ? nil : pipeline
    }

    init(title: String? = nil, symbol: String? = nil, systemPrompt: String? = nil, pipeline: [String]? = nil) {
        self.title = title
        self.symbol = symbol
        self.systemPrompt = systemPrompt
        self.pipeline = pipeline
    }
}

/// Overrides for built-in prompts, keyed by the built-in's stable `DemoPrompt.id`.
/// Synced across Macs like custom prompts (`SyncedPreferences`, JSON `Data`).
@MainActor
final class BuiltInPromptEditStore: ObservableObject {
    static let shared = BuiltInPromptEditStore()
    static let storageKey = "tippi.builtInPromptEdits.v1"

    @Published private(set) var edits: [String: BuiltInPromptEdit] = [:]
    private let defaults: UserDefaults

    /// `defaults` is injectable for tests — they must never touch `.standard`,
    /// which is the installed app's real preferences (CONTRIBUTING.md).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isEdited(_ id: String) -> Bool { edits[id] != nil }

    /// Stores `edit` for built-in `id`. An empty edit removes the override.
    func set(_ edit: BuiltInPromptEdit, for id: String) {
        edits[id] = edit.isEmpty ? nil : edit
        save()
    }

    func reset(id: String) { set(BuiltInPromptEdit(), for: id) }

    func reloadFromDefaults() { load() }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            edits = [:]
            return
        }
        do {
            edits = try JSONDecoder().decode([String: BuiltInPromptEdit].self, from: data)
        } catch {
            // Same rule as CustomPromptStore: never let the next save overwrite
            // an undecodable blob — keep it for manual recovery.
            defaults.set(data, forKey: Self.storageKey + ".corrupt")
            NSLog("Tippi: BuiltInPromptEditStore load failed — preserved blob at \(Self.storageKey).corrupt: \(error.localizedDescription)")
        }
    }

    private func save() {
        // Written even when empty: SyncedPreferences only pushes keys that
        // exist, so removing the key would keep a reset from reaching the
        // other Mac.
        guard let data = try? JSONEncoder().encode(edits) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - One order for built-in and custom prompts

/// The user's order across built-in and custom prompts, as a list of
/// `DemoPrompt.id`s. Synced across Macs as a `[String]`.
///
/// Nothing stored = today's order (built-ins, then custom). IDs not in the list
/// (a built-in added by a later version, a new custom prompt) go to the end in
/// that default order; IDs in the list that no longer exist are ignored.
@MainActor
final class PromptOrderStore: ObservableObject {
    static let shared = PromptOrderStore()
    static let storageKey = "tippi.promptOrder.v1"

    @Published private(set) var order: [String] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Applies a drag in the list the user sees. `currentIDs` is that list, in
    /// its current order; the result is stored as the new order.
    func move(_ currentIDs: [String], fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = currentIDs
        ids.move(fromOffsets: source, toOffset: destination)
        order = ids
        defaults.set(ids, forKey: Self.storageKey)
    }

    func reloadFromDefaults() { load() }

    private func load() {
        order = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    /// Sorts `prompts` (given in default order) by `order`.
    nonisolated static func apply(_ order: [String], to prompts: [DemoPrompt]) -> [DemoPrompt] {
        guard !order.isEmpty else { return prompts }
        var remaining = Dictionary(prompts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [DemoPrompt] = []
        for id in order {
            if let prompt = remaining.removeValue(forKey: id) { result.append(prompt) }
        }
        result += prompts.filter { remaining[$0.id] != nil }
        return result
    }
}

// MARK: - Applying edits and order

extension DemoPrompt {
    /// Pure form of `all`, so the combination is testable without the shared stores.
    static func ordered(
        builtIn: [DemoPrompt],
        custom: [CustomPrompt],
        edits: [String: BuiltInPromptEdit],
        order: [String]
    ) -> [DemoPrompt] {
        let edited = builtIn.map { $0.applying(edits[$0.id]) }
        return PromptOrderStore.apply(order, to: edited + custom.map { $0.asDemoPrompt() })
    }

    /// This prompt with a user's edit applied. The id stays — chains, provider
    /// overrides and the model migration reference built-ins by it.
    func applying(_ edit: BuiltInPromptEdit?) -> DemoPrompt {
        guard let edit else { return self }
        return DemoPrompt(
            id: id,
            title: edit.title ?? title,
            symbol: edit.symbol ?? symbol,
            systemPrompt: edit.systemPrompt ?? instructions,
            pipeline: isChain ? (edit.pipeline ?? pipeline) : nil,
            transform: transform
        )
    }
}
