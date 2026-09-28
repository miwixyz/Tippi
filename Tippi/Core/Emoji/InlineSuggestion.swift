/// Ein Eintrag der Vorschlagsliste, die beim Tippen von „:“ + Buchstaben erscheint.
///
/// Bis 2.17 kannte die Liste nur Emojis; eigene Snippets mit „:“-Kürzel wurden erst
/// ausgeschrieben, wenn das Kürzel vollständig getippt war. Seit 2.18 stehen passende
/// Snippets mit in der Liste (Michael, 2026-09-28) — vor den Emojis, nach derselben
/// Regel wie beim Ausschreiben: eigene Einstellungen schlagen Auslieferungsvorgaben.
enum InlineSuggestion: Identifiable, Hashable {
    case emoji(Emoji)
    /// `preview` ist eine einzeilige, gekürzte Vorschau des Ersetzungstexts.
    case snippet(trigger: String, preview: String)

    var id: String {
        switch self {
        case .emoji(let emoji): return "emoji:\(emoji.id)"
        case .snippet(let trigger, _): return "snippet:\(trigger)"
        }
    }
}
