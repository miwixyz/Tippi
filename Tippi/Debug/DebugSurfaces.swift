#if DEBUG
import SwiftUI

/// Weitere schwebende Oberflächen für Bilder der Bild-Testkopie (`tippictl snapshot <name>`). Nur feste Demo-Inhalte im Code,
/// nie echte Daten (B5 in docs/SECURE-DESIGN-befehlskanal.md): keine eigenen Prompts, Snippets, Notizen, Verlauf.
@MainActor
enum DebugSurfaces {
    // `nonisolated`: reine Konstanten, `DebugCommand.snapshotWindows` liest sie außerhalb des Hauptthreads.
    nonisolated static let emojiSuggestion = "emojivorschlag"
    nonisolated static let emojiPicker = "emojipicker"
    nonisolated static let selectionBar = "auswahlleiste"
    /// Nicht „uebersetzen“: dieser Name bleibt gesperrt (B5, `DebugCommandTests`), denn das echte Fenster zeigt echten Text.
    nonisolated static let translate = "uebersetzenbild"
    nonisolated static let toast = "toast"
    nonisolated static let recording = "aufnahme"
    nonisolated static let correction = "korrektur"
    nonisolated static let popupVoice = "popupsprache"
    nonisolated static let autocomplete = "vorschlag"

    nonisolated static let ids: Set<String> = [emojiSuggestion, emojiPicker, selectionBar, translate, toast, recording, correction,
                                   popupVoice, autocomplete]

    /// Raum rundherum, damit Schatten im Bild nicht an der Fensterkante abgeschnitten werden.
    private static func framed<V: View>(_ view: V) -> AnyView {
        AnyView(view.padding(24))
    }

    static func view(for id: String) -> AnyView? {
        guard ids.contains(id) else { return nil }
        return baseView(for: id)
    }

    private static func baseView(for id: String) -> AnyView? {
        switch id {
        case emojiSuggestion:
            EmojiDatabase.shared.load()
            let picker = EmojiPickerModel(database: EmojiDatabase.shared)
            picker.query = "daumen"
            var suggestions = picker.results.prefix(3).map { InlineSuggestion.emoji($0) }
            suggestions.append(.snippet(trigger: "mfg", preview: "Mit freundlichen Grüßen"))
            let model = EmojiSuggestionModel()
            model.suggestions = suggestions
            return framed(EmojiSuggestionView(model: model) { _ in })
        case emojiPicker:
            EmojiDatabase.shared.load()
            let model = EmojiPickerModel(database: EmojiDatabase.shared)
            model.query = "herz"
            return framed(EmojiPickerView(model: model, onPick: { _ in }, onClose: {}))
        case selectionBar:
            return framed(SelectionActionBarView(onAction: { _ in }, onTranslate: {}, characterCount: 104,
                                                  currencyTargets: ["USD", "GBP", "CHF"]))
        case translate:
            return framed(TranslateQuickView(onClose: {}, audioRecorder: AudioRecorder(),
                                             initialText: "Hallo Anna, danke für das Update.",
                                             onReplace: { _ in },
                                             previewState: .result(text: "Hello Anna, thank you for the update.",
                                                                   providerDisplay: "Demo")))
        case toast:
            return AnyView(ToastView(message: "Text ersetzt"))
        case recording:
            return framed(RecordingIndicatorView(mode: .recording, recorder: AudioRecorder(), aiEnabled: true,
                                                 providerName: "Demo", source: .standard))
        case correction:
            return framed(DictationCorrectionEditor(
                original: .init(heard: "tippy", replacement: "Tippi"), dismiss: {}))
        case popupVoice:
            return AnyView(PromptPopupView(
                prompts: Array(DemoPrompt.builtIn.prefix(4)), localActions: [], localActionsReady: true,
                selectedCharacterCount: 104, onSelect: { _ in }, onDismiss: {},
                audioRecorder: AudioRecorder(), onVoiceTranscribed: { _ in }, voiceMode: .voicePrompt,
                showsVoiceControlsAlways: true))
        case autocomplete:
            return framed(HStack(spacing: 0) {
                Text("Danke für die schnelle Rückmeldung, ich melde mich").foregroundStyle(FamilyTheme.textPrimary)
                AutocompleteSuggestionView(text: " am Freitag bei dir.", fontSize: 14,
                                           hint: .init(key: "⇥", label: "Wort"), animateIn: false)
            }
            .font(.system(size: 14))
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(FamilyTheme.card)))
        default:
            return nil
        }
    }
}
#endif
