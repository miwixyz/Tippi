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

    /// 16 built-in prompts grouped by intent. Wording is deliberately rigorous:
    /// every prompt names what to do, what NOT to do (so small models stop
    /// padding with "Here is the improved text:"), enforces `{language}` to
    /// prevent accidental translation, and ends with a strict "Return ONLY"
    /// clause for parseable single-block output.
    static var builtIn: [DemoPrompt] {
        [
            // ── Core transformations ──────────────────────────────────────────
            DemoPrompt(
                id: "improve",
                title: String(localized: "prompt.improve"),
                symbol: "wand.and.stars",
                systemPrompt: """
                You are a text editor. Rewrite the following text to be clearer, more natural, and better flowing. Keep the exact same meaning and approximately the same length. Stay in {language} — do not translate. Do not add quotes, do not add introductions like "Here is the improved text:", do not explain your changes. Return ONLY the rewritten text.
                """,
                transform: { @Sendable in Self.localImprove($0) }
            ),
            DemoPrompt(
                id: "fixGrammar",
                title: String(localized: "prompt.fixGrammar"),
                symbol: "checkmark.seal",
                systemPrompt: """
                You are a proofreader. Fix ONLY spelling, punctuation, and grammar errors in the following text. Preserve every word choice, sentence structure, tone, and formatting exactly as written — even if you would phrase it differently. Stay in {language}. Return ONLY the corrected text, nothing else.
                """,
                transform: { @Sendable in Self.localFixGrammar($0) }
            ),
            DemoPrompt(
                id: "shorten",
                title: String(localized: "prompt.shorten"),
                symbol: "arrow.down.right.and.arrow.up.left",
                systemPrompt: """
                Rewrite the following text to be roughly 30% shorter. Keep all factual information and the original tone. Remove filler words, redundant phrases, and rambling. Stay in {language}. Return ONLY the shortened text, no commentary.
                """,
                transform: { @Sendable in Self.localShorten($0) }
            ),
            DemoPrompt(
                id: "lengthen",
                title: String(localized: "prompt.lengthen"),
                symbol: "text.append",
                systemPrompt: """
                Expand the following text by about 50% with relevant context, detail, or examples. Keep the original tone and message. Do not pad with filler, generic platitudes, or invented facts. Stay in {language}. Return ONLY the expanded text.
                """,
                transform: { @Sendable in $0 + "\n\n(Local demo — add an API key in Settings for real AI expansion.)" }
            ),

            // ── Tone & style ──────────────────────────────────────────────────
            DemoPrompt(
                id: "makeFormal",
                title: String(localized: "prompt.makeFormal"),
                symbol: "briefcase",
                systemPrompt: """
                Rewrite the following text in a formal, professional tone suitable for business correspondence. Replace casual phrases and slang with neutral or polite alternatives, remove filler. Keep the original message. Stay in {language}. Return ONLY the rewritten text.
                """,
                transform: { @Sendable text in "[Formal] \(text) [local demo]" }
            ),
            DemoPrompt(
                id: "makeCasual",
                title: String(localized: "prompt.makeCasual"),
                symbol: "bubble.left",
                systemPrompt: """
                Rewrite the following text in a casual, conversational tone — like writing to a friend. Use everyday words, short sentences, and contractions where natural. Remove formal phrases and stiff wording. Stay in {language}. Return ONLY the rewritten text.
                """,
                transform: { @Sendable text in "[Casual] \(text) [local demo]" }
            ),
            DemoPrompt(
                id: "simplify",
                title: String(localized: "prompt.simplify"),
                symbol: "textformat.size",
                systemPrompt: """
                Rewrite the following text so a 10-year-old can understand it. Use short sentences, common words, and active voice. Replace every technical term with a plain-language alternative or short explanation. Stay in {language}. Return ONLY the simplified text.
                """,
                transform: { @Sendable in Self.localSimplify($0) }
            ),
            DemoPrompt(
                id: "humanize",
                title: String(localized: "prompt.humanize"),
                symbol: "sparkles",
                systemPrompt: """
                Rewrite the following AI-generated or stiff text to sound like a real person wrote it. Remove these AI tells: corporate buzzwords, hedge phrases ("it's important to note", "as we navigate", "in today's world"), em-dashes used as flow connectors, generic openings, passive voice, three-item list sentences, and bombastic adjectives ("seamless", "robust", "comprehensive"). Use varied sentence length and natural word choice. Keep the original message. Stay in {language}. Return ONLY the rewritten text.
                """,
                transform: { @Sendable text in text + " [humanized — local demo]" }
            ),

            // ── Structure (list-formatting) ───────────────────────────────────
            DemoPrompt(
                id: "summarize",
                title: String(localized: "prompt.summarize"),
                symbol: "list.bullet.clipboard",
                systemPrompt: """
                Summarize the following text as 3 concise bullet points starting with "• ". Capture only the most important facts. Stay in {language}. Return ONLY the 3 bullet points, no introduction, no closing remarks.
                """,
                transform: { @Sendable in Self.localSummarize($0) }
            ),
            DemoPrompt(
                id: "tldr",
                title: String(localized: "prompt.tldr"),
                symbol: "text.alignleft",
                systemPrompt: """
                Summarize the following text in 1–2 sentences maximum. No bullet points. No introduction. No labels like "TL;DR:" or "Summary:". Just the essence as plain prose. Stay in {language}. Return ONLY the summary sentences.
                """,
                transform: { @Sendable text in "TL;DR: " + String(text.prefix(120)) + "… [local demo]" }
            ),
            DemoPrompt(
                id: "bulletpoints",
                title: String(localized: "prompt.bulletpoints"),
                symbol: "list.dash",
                systemPrompt: """
                Convert the following text into a bullet-point list. Each distinct thought, statement, or fact becomes one bullet starting with "• ". Do not condense or summarize — preserve every idea. Stay in {language}. Return ONLY the bullet list.
                """,
                transform: { @Sendable text in text.split(separator: ".").map { "• \($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n") }
            ),
            DemoPrompt(
                id: "keypoints",
                title: String(localized: "prompt.keypoints"),
                symbol: "list.bullet",
                systemPrompt: """
                Extract the key points from the following text as compact bullet points starting with "• ". Maximum 5 points. Each point is one short phrase, not a full sentence. Capture the essence, not every detail. Stay in {language}. Return ONLY the key points.
                """,
                transform: { @Sendable in Self.localSummarize($0) }
            ),
            DemoPrompt(
                id: "todos",
                title: String(localized: "prompt.todos"),
                symbol: "checkmark.circle",
                systemPrompt: """
                Extract every actionable task, to-do, or next step from the following text. Format as a bullet list starting with "• ", each bullet beginning with an action verb (e.g. "Call", "Send", "Review", "Anrufen", "Senden", "Prüfen"). Include implicit tasks too. If there are no actionable items, return exactly: "No action items found." Stay in {language}. Return ONLY the task list.
                """,
                transform: { @Sendable text in "• " + text.replacingOccurrences(of: ".", with: "\n• ") + " [local demo]" }
            ),

            // ── Audience-specific ─────────────────────────────────────────────
            DemoPrompt(
                id: "explainForChild",
                title: String(localized: "prompt.explainForChild"),
                symbol: "lightbulb",
                systemPrompt: """
                Explain the following text as if to a 10-year-old. Use short sentences, common words, and one concrete everyday example or analogy. No technical terms — replace each with a simple alternative. Stay in {language}. Return ONLY the explanation.
                """,
                transform: { @Sendable in Self.localSimplify($0) }
            ),

            // ── Communication ─────────────────────────────────────────────────
            DemoPrompt(
                id: "emailReply",
                title: String(localized: "prompt.emailReply"),
                symbol: "arrowshape.turn.up.left",
                systemPrompt: """
                Write a friendly, professional reply to the following incoming email. Keep it short (3–5 sentences). Start with an appropriate greeting matching the formality of the original. End with a neutral closing (e.g. "Best regards", "Viele Grüße") — do NOT invent or add a specific name. Stay in {language}. Return ONLY the reply text.
                """,
                transform: { @Sendable text in "[Reply draft] \(String(text.prefix(80)))… [local demo]" }
            ),

            // ── Social media ──────────────────────────────────────────────────
            DemoPrompt(
                id: "linkedinPost",
                title: String(localized: "prompt.linkedinPost"),
                symbol: "person.crop.rectangle",
                systemPrompt: """
                Rewrite the following text as a LinkedIn post. First-person voice. Attention-grabbing first line (the "hook"). 1–3 short paragraphs separated by blank lines (LinkedIn rewards line breaks). One clear takeaway. End with 2–3 relevant hashtags maximum. Avoid emoji floods (1–2 max), avoid the cliché "Thoughts?" close. Stay in {language}. Return ONLY the post.
                """,
                transform: { @Sendable text in "[LinkedIn] \(text) [local demo]" }
            ),
            DemoPrompt(
                id: "instagramCaption",
                title: String(localized: "prompt.instagramCaption"),
                symbol: "camera",
                systemPrompt: """
                Rewrite the following text as an Instagram caption. Personal, emotional voice. Attention-grabbing first sentence — must work even after the "...more" truncation. Maximum 150 words. End with 3–5 relevant hashtags on a separate line. Stay in {language}. Return ONLY the caption.
                """,
                transform: { @Sendable text in "[IG] \(text) [local demo]" }
            ),
            DemoPrompt(
                id: "facebookPost",
                title: String(localized: "prompt.facebookPost"),
                symbol: "bubble.middle.bottom",
                systemPrompt: """
                Rewrite the following text as a Facebook post. Conversational and personal — like sharing with friends. Storytelling first paragraph (the hook). 1–4 short paragraphs. Sparing hashtags (0–2 maximum). No marketing-speak. Stay in {language}. Return ONLY the post.
                """,
                transform: { @Sendable text in "[FB] \(text) [local demo]" }
            ),

            // ── Context-aware ─────────────────────────────────────────────────
            DemoPrompt(
                id: "adaptForApp",
                title: String(localized: "prompt.adaptForApp"),
                symbol: "macwindow",
                systemPrompt: """
                You are writing a message for {app_name}. Adapt the following text to fit that context:
                – Slack, WhatsApp, Telegram, Discord, iMessage: casual, max 2–3 sentences, no greeting
                – Mail, Outlook, Gmail, Spark: formal, appropriate greeting and closing
                – Notes, Notion, Obsidian, Bear: structured bullet points
                – LinkedIn: professional, first-person voice, no hashtags
                – Anywhere else: clear and professional

                Keep the original message. Stay in {language}. Return ONLY the rewritten text.
                """,
                transform: { @Sendable text in "[\(text)] [local demo — trigger in an app for context-aware output]" }
            ),

            // ── Translations ──────────────────────────────────────────────────
            DemoPrompt(
                id: "translateDE",
                title: String(localized: "prompt.translateDE"),
                symbol: "globe.europe.africa",
                systemPrompt: """
                Translate the following text into natural, modern German (Du-Form unless the source is clearly formal). Preserve the original tone and meaning. If the text is already in German, fix only obvious errors. Return ONLY the German translation.
                """,
                transform: { @Sendable in "[Demo DE] " + $0 }
            ),
            DemoPrompt(
                id: "translateEN",
                title: String(localized: "prompt.translateEN"),
                symbol: "globe.americas",
                systemPrompt: """
                Translate the following text into natural, modern English. Preserve the original tone and meaning. If the text is already in English, fix only obvious errors. Return ONLY the English translation.
                """,
                transform: { @Sendable in "[Demo EN] " + $0 }
            ),
            DemoPrompt(
                id: "translateES",
                title: String(localized: "prompt.translateES"),
                symbol: "globe",
                systemPrompt: """
                Translate the following text into natural, modern Spanish (Castilian unless the source clearly suggests Latin American Spanish). Preserve the original tone and meaning. If the text is already in Spanish, fix only obvious errors. Return ONLY the Spanish translation.
                """,
                transform: { @Sendable in "[Demo ES] " + $0 }
            ),
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

    private static func localSummarize(_ input: String) -> String {
        let sentences = input
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let points = sentences.prefix(3).map { "• \($0)." }
        return points.joined(separator: "\n") + "\n[local demo]"
    }

    private static func localSimplify(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines) + " [local demo — simplified]"
    }
}
