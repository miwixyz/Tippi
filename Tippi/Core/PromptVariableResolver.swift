import AppKit
import NaturalLanguage

/// Resolves `{variable}` tokens in prompt templates before they are sent to the LLM.
///
/// Supported tokens:
/// - `{clipboard}`      — current pasteboard string (empty if none)
/// - `{app_name}`       — name of the source app, e.g. "Mail" or "Safari"
/// - `{language}`       — detected language of the selected text, e.g. "German",
///                        or `languageFallback` when detection isn't confident
/// - `{selected_text}`  — the captured/selected text itself
enum PromptVariableResolver {

    struct Context {
        let selectedText: String
        let appName: String
        let clipboardText: String
        let language: String

        /// Build a resolution context for the current trigger.
        /// Reads the clipboard and detects language at construction time.
        init(selectedText: String, appName: String) {
            self.selectedText = selectedText
            self.appName = appName
            self.clipboardText = NSPasteboard.general.string(forType: .string) ?? ""

            self.language = Self.detectLanguage(in: selectedText)
        }

        /// Phrase substituted for `{language}` when detection isn't confident.
        /// Deliberately a valid instruction fragment, not an empty string: 21 of
        /// the 24 built-in prompts embed the token as "Stay in {language}", so an
        /// empty value rendered the literal, meaningless order "Stay in ."
        static let languageFallback = "the same language as the input"

        /// Minimum confidence before trusting `NLLanguageRecognizer`. Measured
        /// against real short inputs (2026-09-02): genuine German scored
        /// 0.93–1.00, while every misclassification scored ≤ 0.80 — "LG Michael"
        /// came back Polish at 0.21 and "CINEWEB" Polish at 0.43. Below this
        /// bar the prompt would actively order the model into the WRONG
        /// language, which is worse than not naming one at all.
        private static let minimumConfidence = 0.85

        /// Detects the input's language, or returns `languageFallback` when the
        /// sample is too short/ambiguous to be sure. Only a 500-character sample
        /// is analysed — more text costs time without improving accuracy.
        private static func detectLanguage(in text: String) -> String {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(text.prefix(500)))
            guard let top = recognizer.languageHypotheses(withMaximum: 1)
                    .max(by: { $0.value < $1.value }),
                  top.value >= minimumConfidence,
                  let name = Locale(identifier: "en")
                    .localizedString(forLanguageCode: top.key.rawValue)
            else {
                return languageFallback
            }
            return name
        }
    }

    /// Replace all known `{token}` placeholders in `template` with their resolved values.
    static func resolve(template: String, context: Context) -> String {
        let values = [
            "{clipboard}": context.clipboardText,
            "{app_name}": context.appName,
            "{language}": context.language,
            "{selected_text}": context.selectedText
        ]

        var resolved = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if let match = values.first(where: { token, _ in
                template[cursor...].hasPrefix(token)
            }) {
                resolved += match.value
                cursor = template.index(cursor, offsetBy: match.key.count)
            } else {
                resolved.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }
        return resolved
    }
}
