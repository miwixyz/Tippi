import Foundation

/// A prompt entry shown in the cursor popup.
/// Each has a system prompt for the LLM and a local-fallback transform.
struct DemoPrompt: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let systemPrompt: String
    let transform: @Sendable (String) -> String

    static func == (lhs: DemoPrompt, rhs: DemoPrompt) -> Bool { lhs.id == rhs.id }

    /// Built-in + user-defined prompts.
    @MainActor
    static var all: [DemoPrompt] {
        builtIn + CustomPromptStore.shared.prompts.map { $0.asDemoPrompt() }
    }

    static var builtIn: [DemoPrompt] {
        [
            DemoPrompt(
                id: "improve",
                title: String(localized: "prompt.improve"),
                symbol: "wand.and.stars",
                systemPrompt: "Improve the writing quality of the following text. Keep the original language, meaning, and approximate length. Return only the improved text without any commentary, quotes, or formatting.",
                transform: { @Sendable in Self.localImprove($0) }
            ),
            DemoPrompt(
                id: "fixGrammar",
                title: String(localized: "prompt.fixGrammar"),
                symbol: "checkmark.seal",
                systemPrompt: "Fix only spelling, punctuation, and grammar errors in the following text. Do not change wording, tone, or style beyond what is required to be correct. Keep the original language. Return only the corrected text.",
                transform: { @Sendable in Self.localFixGrammar($0) }
            ),
            DemoPrompt(
                id: "translateDE",
                title: String(localized: "prompt.translateDE"),
                symbol: "globe.europe.africa",
                systemPrompt: "Translate the following text into German. Preserve tone and formatting. Return only the German translation.",
                transform: { @Sendable in "[Demo DE] " + $0 }
            ),
            DemoPrompt(
                id: "translateEN",
                title: String(localized: "prompt.translateEN"),
                symbol: "globe.americas",
                systemPrompt: "Translate the following text into English. Preserve tone and formatting. Return only the English translation.",
                transform: { @Sendable in "[Demo EN] " + $0 }
            ),
            DemoPrompt(
                id: "shorten",
                title: String(localized: "prompt.shorten"),
                symbol: "arrow.down.right.and.arrow.up.left",
                systemPrompt: "Rewrite the following text to be about 30% shorter while keeping all key information. Keep the original language. Return only the shortened text.",
                transform: { @Sendable in Self.localShorten($0) }
            ),
            DemoPrompt(
                id: "lengthen",
                title: String(localized: "prompt.lengthen"),
                symbol: "text.append",
                systemPrompt: "Expand the following text with relevant context and detail. Aim for about 50% more length. Keep the original language and tone. Return only the expanded text.",
                transform: { @Sendable in $0 + "\n\n(Local demo — add an API key in Settings for real AI expansion.)" }
            )
        ]
    }

    // MARK: - Local fallbacks (used when no LLM provider is configured)

    private static func localImprove(_ input: String) -> String {
        var text = input
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = text.components(separatedBy: ".")
        text = sentences.map { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return piece }
            return " " + trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        }.joined(separator: ".")
        return text.trimmingCharacters(in: .whitespaces) + " [✨ local demo]"
    }

    private static func localFixGrammar(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return input }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if !text.hasSuffix(".") && !text.hasSuffix("!") && !text.hasSuffix("?") {
            text += "."
        }
        return text + " [✓ local demo]"
    }

    private static func localShorten(_ input: String) -> String {
        let words = input.split(separator: " ")
        guard words.count > 5 else { return input + " [local demo]" }
        let kept = words.prefix(max(1, words.count * 2 / 3))
        return kept.joined(separator: " ") + "… [local demo]"
    }
}
