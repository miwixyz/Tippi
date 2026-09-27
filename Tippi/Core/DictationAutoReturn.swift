import Foundation

// MARK: - Auto-Return after dictation

/// "Press Return after inserting" — for chat inputs where Return sends.
/// Split out of `DictationController.swift` (file length) on 2026-09-27; the
/// storage key stays in the `dictation.` namespace that
/// `scripts/real-defaults-guard.sh` watches.
extension DictationSettings {
    private static let autoReturnAppsKey = "dictation.autoReturn.bundleIDs.v1"

    /// Apps in which Tippi presses Return right after inserting a dictation —
    /// for chat inputs like Claude, where Return sends. Command-capable apps get
    /// it only for text the AI left untouched (see below). Empty by default,
    /// i.e. the feature is off until the user adds an app.
    static var autoReturnBundleIDs: [String] {
        get { store.stringArray(forKey: autoReturnAppsKey) ?? [] }
        set { store.set(AutocompleteSettings.normalized(newValue), forKey: autoReturnAppsKey) }
    }

    enum AutoReturnDecision: Equatable {
        case press
        case skip
        /// Would have pressed, but this is a terminal-like app and the AI
        /// cleanup changed the text — Return is withheld and the user told why.
        case blocked
    }

    /// Apps where Return can run a command: terminals, editors with a built-in
    /// terminal, coding agents. Here Return follows only text the AI did not
    /// touch. Two word/character heuristics were tried first and both were
    /// bypassed in review (`(!!)`, `./*`, a dropped "nicht" — 2026-09-27), so
    /// the rule is exact equality, decided by Michael: "Terminals streng".
    /// Accepted residual risk: custom-word variants ("Tipi → Tippi") are applied
    /// during transcription, so they are already part of `raw`, and they sync
    /// via iCloud — a rule planted there would pass. Needs a compromised Apple
    /// account or second Mac (Rafter 2026-09-27, left as is by decision).
    /// Measured on this Mac 2026-09-27: Terminal, VS Code, Codex. The rest from
    /// the vendors' published IDs, not measured (not installed here).
    nonisolated static let commandCapableBundleIDs: Set<String> = [
        "com.apple.Terminal",               // gemessen
        "com.microsoft.VSCode",             // gemessen
        "com.openai.codex",                 // gemessen
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "com.todesktop.230313mzl4w4u92",    // Cursor
        "dev.zed.Zed",
    ]

    /// Return is only pressed when the app we insert into is on the list AND was
    /// already frontmost BEFORE insertion (the clipboard fallback re-activates the
    /// target itself, so checking afterwards proves nothing — Rafter review
    /// 2026-09-27) AND something is inserted AND — in a command-capable app —
    /// the inserted text is exactly what was dictated.
    nonisolated static func autoReturnDecision(
        raw: String,
        inserted text: String,
        targetBundleID: String?,
        frontmostBundleID: String?,
        allowed: [String]
    ) -> AutoReturnDecision {
        guard let target = targetBundleID, target == frontmostBundleID,
              allowed.contains(target) else { return .skip }
        let inserted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inserted.isEmpty else { return .skip }
        if commandCapableBundleIDs.contains(target),
           inserted != raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .blocked
        }
        return .press
    }
}
