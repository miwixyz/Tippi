import AVFoundation
import NaturalLanguage

/// Text-to-speech for the Translate Quick Panel. Uses Apple's built-in
/// `AVSpeechSynthesizer` (offline, free) and auto-selects a German or Spanish
/// voice based on the language of the text it is handed — so a German result
/// is read by a German voice and a Spanish result by a Spanish voice, without
/// the user picking anything.
@MainActor
final class TranslateSpeech: ObservableObject {
    static let shared = TranslateSpeech()

    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false

    private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        var onFinish: (() -> Void)?
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onFinish?() }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onFinish?() }
    }
    private let speechDelegate = SpeechDelegate()

    private init() {
        speechDelegate.onFinish = { [weak self] in
            Task { @MainActor in self?.isSpeaking = false }
        }
        synthesizer.delegate = speechDelegate
    }

    /// Speaks the text, or stops if already speaking (toggle). Picks the voice
    /// language from the detected language of `text` (German ⇄ Spanish, with a
    /// German fallback for anything ambiguous — matching the translator's own
    /// fallback).
    func toggle(_ text: String) {
        if isSpeaking {
            stop()
            return
        }
        speak(text)
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: trimmed)
        let langCode = Self.voiceLanguage(for: trimmed)
        utterance.voice = Self.bestVoice(for: langCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Language + voice selection

    /// Detected BCP-47 language code, constrained to the two languages this
    /// feature deals with. Spanish only when clearly Spanish; everything else
    /// falls back to German (the translator's output is always DE or ES).
    private static func voiceLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if recognizer.dominantLanguage == .spanish {
            return "es-ES"
        }
        return "de-DE"
    }

    /// Prefers a higher-quality (enhanced/premium) installed voice for the
    /// language if the user has one, otherwise the system default for that
    /// language. Falls back to nil (AVSpeechSynthesizer then uses the system
    /// default) if no matching voice exists at all.
    private static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let matching = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
        // Enhanced/premium voices sound markedly more natural than the compact
        // default — prefer them when the user has downloaded one
        // (System Settings → Accessibility → Spoken Content → System Voice).
        if let premium = matching.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = matching.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return matching.first ?? AVSpeechSynthesisVoice(language: language)
    }
}
