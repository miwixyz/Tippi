import Foundation

extension DictationController {
    /// Absicht für „Antwort per Sprache" — oder `nil`, dann ist es ein normales Diktat.
    /// Eigene Taste: das ganze Diktat. Sonst nur mit Vorwort in den ersten drei Wörtern
    /// eines normalen Diktats (nicht bei Modi, Mail-Diktat, Sprachnotiz).
    func replyIntent(in raw: String) -> String? {
        guard ReplySettings.isEnabled else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .reply { return text.isEmpty ? nil : text }
        guard source == .standard else { return nil }
        return ReplyLogic.intent(afterPrefixIn: text, prefix: ReplySettings.prefix, variants: ReplySettings.prefixVariants)
    }
}
