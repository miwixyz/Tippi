import AppKit
import NaturalLanguage

/// Resolves `{variable}` tokens in prompt templates before they are sent to the LLM.
///
/// Supported tokens:
/// - `{clipboard}`      — current pasteboard string (empty if none)
/// - `{app_name}`       — name of the source app, e.g. "Mail" or "Safari"
/// - `{language}`       — detected language of the selected text, e.g. "German"
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

            let recognizer = NLLanguageRecognizer()
            recognizer.processString(selectedText)
            if let code = recognizer.dominantLanguage?.rawValue {
                self.language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
            } else {
                self.language = ""
            }
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
