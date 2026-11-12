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

        private static func phrase(_ input: String) -> String? {
            let value = input.precomposedStringWithCanonicalMapping
            guard value.utf8.count <= 160, value.unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                    || CharacterSet.punctuationCharacters.contains($0) || " +&".unicodeScalars.contains($0)
            }), value.contains(where: \.isLetter) else { return nil }
            return value.trimmingCharacters(in: .whitespaces)
        }

        var variant: CustomWordVariants.Rule {
            .init(variants: [heard], target: replacement)
        }
    }

    enum SaveProblem: String {
        case duplicate, limit, noExcerpt, noMatch, deleted
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var recent: String?
    @Published private(set) var rules: [Rule]
    private let defaults: UserDefaults
    private var expiry: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        let rows = defaults.array(forKey: Self.rulesKey) ?? []
        rules = rows.prefix(Self.maxRules).reduce(into: []) { result, value in
            guard let row = value as? [String: String], let heard = row["heard"],
                  let replacement = row["replacement"], let rule = Rule(heard: heard, replacement: replacement),
                  !result.contains(where: { $0.heard.caseInsensitiveCompare(rule.heard) == .orderedSame }) else { return }
            result.append(rule)
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
        var excerpt = transcript.suffix(1_500)
        if excerpt.startIndex != transcript.startIndex,
           !transcript[transcript.index(before: excerpt.startIndex)].isWhitespace {
            excerpt = excerpt.drop(while: { !$0.isWhitespace })
        }
        guard excerpt.contains(where: { !$0.isWhitespace }) else { return }
        recent = String(excerpt)
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.forgetRecent()
        }
    }

    func apply(to text: String) -> String {
        guard enabled, !rules.isEmpty else { return text }
        return Self.applyRules(rules, to: text)
    }

    private static func applyRules(_ rules: [Rule], to text: String) -> String {
        let canonical = text.precomposedStringWithCanonicalMapping
        let corrected = CustomWordVariants.apply(to: canonical, rules: rules.map(\.variant))
        return corrected == canonical ? text : corrected
    }

    func saveProblem(_ rule: Rule, editing original: Rule? = nil) -> SaveProblem? {
        let hasConflict = rules.contains {
            $0 != original && $0.heard.caseInsensitiveCompare(rule.heard) == .orderedSame
        }
        if hasConflict { return .duplicate }
        if let original { return rules.contains(original) ? nil : .deleted }
        guard enabled, let recent else { return .noExcerpt }
        guard rules.count < Self.maxRules else { return .limit }
        let previous = Self.applyRules(rules, to: recent)
        return Self.applyRules(rules + [rule], to: recent) == previous ? .noMatch : nil
    }

    @discardableResult
    func save(_ rule: Rule, editing original: Rule? = nil) -> Bool {
        guard saveProblem(rule, editing: original) == nil else { return false }
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
