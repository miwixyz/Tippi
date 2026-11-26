import AppKit

extension DictationSettings {
    private static let insertSoundKey = "dictation.insertSound.enabled.v1"

    /// „Ton nach dem Einfügen“: a short Tippi sound once the dictated text is in
    /// the target field. Default OFF — a sound is a change people notice.
    static var insertSoundEnabled: Bool {
        get { store.bool(forKey: insertSoundKey) }
        set { store.set(newValue, forKey: insertSoundKey) }
    }
}

/// Plays `tippi.caf` (App-Familie, two marimba notes, 0.22 s) after a dictation
/// was inserted. Never fails silently: a missing or unreadable file is logged.
///
/// Order relative to „Systemton während der Aufnahme stummschalten“: the
/// recorder restores the system output in `AudioRecorder.stop()`, which runs
/// synchronously in `beginTranscription` — long before the text is inserted.
/// A recording that is running *again* (e.g. a new take started meanwhile)
/// would have the output muted and would also record the sound, so the caller
/// passes `recorderActive` and nothing plays then.
///
/// `inserted`: the text really went into the field — no notice from the
/// insertion step (a notice means clipboard fallback or unverified write)
/// and not cancelled.
@MainActor
enum DictationSound {
    static let resourceName = "tippi"
    static let resourceExtension = "caf"

    /// Kept so the sound is not released while playing; replaced on each play.
    private static var current: NSSound?

    static func playAfterInsertion(inserted: Bool, recorderActive: Bool) {
        guard inserted, DictationSettings.insertSoundEnabled else { return }
        guard !recorderActive else {
            dictationLog.notice("insert sound skipped — a recording is running")
            return
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            dictationLog.notice("insert sound missing — \(resourceName, privacy: .public).\(resourceExtension, privacy: .public) not in the app bundle")
            return
        }
        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            dictationLog.notice("insert sound could not be loaded from \(url.lastPathComponent, privacy: .public)")
            return
        }
        current?.stop()
        current = sound
        if !sound.play() {
            dictationLog.notice("insert sound did not start playing")
        }
    }
}
