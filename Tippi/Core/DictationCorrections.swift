import Foundation
import Combine

/// Device-local corrections confirmed by the user. Separate from the synced glossary.
@MainActor
final class DictationCorrections: ObservableObject {
    static let shared = DictationCorrections(defaults: .standard)
    private static let enabledKey = "dictation.corrections.enabled"
    private static let rulesKey = "dictation.corrections.rules.v1"
    private static let maxRules = 100

    struct Rule: Hashable, Identifiable {
        let heard: String
        let replacement: String
        var id: String { heard }

        init?(heard: String, replacement: String) {
            guard let heard = Self.phrase(heard), let replacement = Self.phrase(replacement),
                  heard != replacement,
                  heard.split(separator: " ").filter({ $0.contains(where: \.isLetter) }).count >= 2 else { return nil }
            self.heard = heard
            self.replacement = replacement
        }

        private static func phrase(_ value: String) -> String? {
            guard value.utf8.count <= 160, value.unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                    || " -–.'’".unicodeScalars.contains($0)
            }), value.contains(where: \.isLetter) else { return nil }
            return value.trimmingCharacters(in: .whitespaces)
        }

        var variant: CustomWordVariants.Rule {
            .init(variants: [heard], target: replacement)
        }
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var recent: String?
    @Published private(set) var rules: [Rule]
    private let defaults: UserDefaults
    private var expiry: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        let rows = defaults.array(forKey: Self.rulesKey) as? [[String: String]] ?? []
        rules = rows.prefix(Self.maxRules).compactMap { row in
            guard let heard = row["heard"], let replacement = row["replacement"] else { return nil }
            return Rule(heard: heard, replacement: replacement)
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        if !value { forgetRecent() }
    }

    func forgetRecent() {
        expiry?.cancel()
        expiry = nil
        recent = nil
    }

    func offer(_ transcript: String) {
        guard enabled, !transcript.isEmpty else { return }
        forgetRecent()
        recent = String(transcript.suffix(1_500))
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            self?.forgetRecent()
        }
    }

    func apply(to text: String) -> String {
        guard enabled else { return text }
        return CustomWordVariants.apply(to: text, rules: rules.map(\.variant))
    }

    func canSave(_ rule: Rule, editing original: Rule? = nil) -> Bool {
        let hasConflict = rules.contains {
            $0 != original && $0.heard.caseInsensitiveCompare(rule.heard) == .orderedSame
        }
        guard !hasConflict else { return false }
        if let original { return rules.contains(original) }
        guard enabled, rules.count < Self.maxRules, let recent else { return false }
        return CustomWordVariants.apply(to: recent, rules: [rule.variant]) != recent
    }

    @discardableResult
    func save(_ rule: Rule, editing original: Rule? = nil) -> Bool {
        guard canSave(rule, editing: original) else { return false }
        if let original, let index = rules.firstIndex(of: original) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persist()
        return true
    }

    func remove(_ rule: Rule) {
        rules.removeAll { $0 == rule }
        persist()
    }

    private func persist() {
        defaults.set(rules.map { ["heard": $0.heard, "replacement": $0.replacement] }, forKey: Self.rulesKey)
    }
}
