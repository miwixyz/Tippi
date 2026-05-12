import Foundation

/// A prompt the user created in Settings → Prompts.
/// Stored in UserDefaults as JSON.
struct CustomPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var symbol: String
    var systemPrompt: String

    init(id: UUID = UUID(), title: String, symbol: String, systemPrompt: String) {
        self.id = id
        self.title = title
        self.symbol = symbol.isEmpty ? "wand.and.stars" : symbol
        self.systemPrompt = systemPrompt
    }

    func asDemoPrompt() -> DemoPrompt {
        let promptTitle = title
        return DemoPrompt(
            id: "custom-\(id.uuidString)",
            title: title,
            symbol: symbol,
            systemPrompt: systemPrompt,
            transform: { @Sendable text in
                "[\(promptTitle)] \(text)\n\n(Local demo — add an AI key in Settings → Providers.)"
            }
        )
    }
}

@MainActor
final class CustomPromptStore: ObservableObject {
    static let shared = CustomPromptStore()

    @Published private(set) var prompts: [CustomPrompt] = []

    private let storageKey = "tippi.customPrompts.v1"

    private init() {
        load()
    }

    func add(title: String, symbol: String, systemPrompt: String) {
        prompts.append(CustomPrompt(title: title, symbol: symbol, systemPrompt: systemPrompt))
        save()
    }

    func update(_ prompt: CustomPrompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        prompts[index] = prompt
        save()
    }

    func delete(id: UUID) {
        prompts.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        prompts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([CustomPrompt].self, from: data) {
            prompts = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
