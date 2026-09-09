import Combine
import CryptoKit
import Foundation
import os

private let storeLog = Logger(subsystem: "com.tippi.app", category: "snippet-store")

/// What a matched trigger resolves to — either a static app-managed
/// replacement, or a full Espanso match (which may need shell/date vars
/// resolved before the text is known).
enum SnippetAction {
    case staticText(String)
    case espansoMatch(SnippetMatch)
}

/// One loaded Espanso match file, plus the bookkeeping the per-file consent
/// gate needs. `containsShellVars` only changes what the approval prompt
/// says (explicit command listing vs. a plain trigger listing) — every file
/// needs approval, not just ones that shell out.
struct LoadedEspansoFile: Identifiable, Equatable {
    let id: String // file path — stable across reloads
    let url: URL
    var matchFile: EspansoMatchFile
    var containsShellVars: Bool
    var isApproved: Bool
}

/// Owns both snippet sources — app-managed (JSON, editable in Settings) and
/// imported Espanso YAML files (read-only, file stays the source of truth) —
/// and merges them into the single trigger→action lookup the keystroke
/// monitor needs. Also owns the per-file consent gate: ANY file in the
/// watched directory is inactive until its exact current content has been
/// approved once — not just files with `type: shell` vars. A plain
/// static-text file could otherwise silently redefine an existing trigger
/// (e.g. hijack ":mw" to a different address) the moment anything else with
/// write access to that directory drops it there, with zero visible
/// consent — gating only shell execution would have missed that.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var appSnippets: [AppSnippet] = []
    @Published private(set) var espansoFiles: [LoadedEspansoFile] = []

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    /// Prepended to a newly created app snippet's shortcut if the user didn't
    /// already type it themselves — the "easier than Espanso" default, but
    /// changeable so it doesn't have to be Espanso's usual `:`.
    @Published var defaultPrefix: String {
        didSet { defaults.set(defaultPrefix, forKey: Keys.prefix) }
    }
    @Published var matchDirectory: URL {
        didSet {
            defaults.set(matchDirectory.path, forKey: Keys.matchDir)
            reloadEspansoFiles()
        }
    }

    /// File awaiting a shell-command consent decision — drives the warning
    /// sheet in Settings. One at a time, so the prompt always names one
    /// concrete file and its exact commands, never a vague blanket warning.
    @Published var pendingFileApproval: LoadedEspansoFile?

    private enum Keys {
        static let enabled = "tippi.snippets.enabled.v1"
        static let prefix = "tippi.snippets.prefix.v1"
        static let matchDir = "tippi.snippets.matchDir.v1"
        static let appSnippetsFile = "AppSnippets.json"
        static func approvedHashKey(path: String) -> String {
            "tippi.snippets.approvedShellHash.\(path)"
        }
    }

    private let fileManager = FileManager.default
    /// Injected so unit tests can point persistence at a temp directory and
    /// an ephemeral defaults suite instead of writing into Michael's real
    /// `~/Library/Application Support/Tippi` and the app's real UserDefaults
    /// domain. Production always uses the defaults (nil / `.standard`).
    private let appSupportRoot: URL
    private let defaults: UserDefaults

    init(appSupportRoot: URL? = nil, userDefaults: UserDefaults = .standard) {
        self.appSupportRoot = appSupportRoot ?? Self.systemAppSupportDirectory
        self.defaults = userDefaults
        self.isEnabled = userDefaults.bool(forKey: Keys.enabled)
        self.defaultPrefix = userDefaults.string(forKey: Keys.prefix) ?? ":"
        if let saved = userDefaults.string(forKey: Keys.matchDir) {
            self.matchDirectory = URL(fileURLWithPath: saved)
        } else {
            self.matchDirectory = (appSupportRoot ?? Self.systemAppSupportDirectory)
                .appendingPathComponent("espanso/match", isDirectory: true)
        }
        loadAppSnippets()
        reloadEspansoFiles()
    }

    /// Espanso's real default macOS config location (`espanso path` reports
    /// the same directory) — pointing Tippi at it picks up exactly what's
    /// already there, no file moves needed for the migration.
    static var defaultEspansoMatchDirectory: URL {
        systemAppSupportDirectory.appendingPathComponent("espanso/match", isDirectory: true)
    }

    private static var systemAppSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private var tippiSupportDirectory: URL {
        let dir = appSupportRoot.appendingPathComponent("Tippi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - App-managed snippets

    private var appSnippetsURL: URL {
        tippiSupportDirectory.appendingPathComponent(Keys.appSnippetsFile)
    }

    private func loadAppSnippets() {
        guard let data = try? Data(contentsOf: appSnippetsURL),
              let decoded = try? JSONDecoder().decode([AppSnippet].self, from: data) else {
            appSnippets = []
            return
        }
        appSnippets = decoded
    }

    private func saveAppSnippets() {
        guard let data = try? JSONEncoder().encode(appSnippets) else { return }
        try? data.write(to: appSnippetsURL, options: .atomic)
    }

    /// Prepends `defaultPrefix` only for a bare word (e.g. "mlg" → ":mlg").
    /// A shortcut that already starts with punctuation — any punctuation,
    /// not just the configured prefix — is treated as a deliberately
    /// complete trigger and left untouched, so a one-off different prefix
    /// (";foo", "##bar") still works by just typing it in full.
    func addSnippet(shortcut: String, replacement: String, vars: [SnippetVar] = []) {
        let trimmed = shortcut.trimmingCharacters(in: .whitespaces)
        let looksLikeACompleteTrigger = trimmed.first.map { !$0.isLetter && !$0.isNumber } ?? true
        let trigger = looksLikeACompleteTrigger ? trimmed : defaultPrefix + trimmed
        appSnippets.append(AppSnippet(trigger: trigger, replacement: replacement, vars: vars))
        saveAppSnippets()
    }

    func updateSnippet(_ snippet: AppSnippet) {
        guard let idx = appSnippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        appSnippets[idx] = snippet
        saveAppSnippets()
    }

    func removeSnippet(_ snippet: AppSnippet) {
        appSnippets.removeAll { $0.id == snippet.id }
        saveAppSnippets()
    }

    // MARK: - Espanso file import (read-only)

    func reloadEspansoFiles() {
        // `contentsOfDirectory(at:)` (the URL-based overload) throws ENOTDIR
        // when `matchDirectory` is itself a symlink to a directory — verified
        // directly: it works fine on the resolved target path, and
        // `FileManager.fileExists` correctly reports it as a directory, but
        // this specific call does not follow the link. Espanso's real macOS
        // config path is routinely symlinked (e.g. into a synced vault/dotfiles
        // repo, as it is here), so resolving first isn't an edge case — it's
        // the common case for anyone who doesn't keep match files in the
        // literal default location.
        let resolvedDirectory = matchDirectory.resolvingSymlinksInPath()
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: resolvedDirectory, includingPropertiesForKeys: nil)
        } catch {
            // This used to be a silently swallowed `try?` — exactly the
            // failure class that hides real problems as "nothing to do
            // here". A directory that can't be listed is worth a log line,
            // not silence.
            storeLog.error("could not list match directory \(resolvedDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            espansoFiles = []
            return
        }

        var loaded: [LoadedEspansoFile] = []
        for url in entries where url.pathExtension == "yml" || url.pathExtension == "yaml" {
            do {
                let matchFile = try EspansoYAMLParser.parseFile(at: url)
                let hasShell = matchFile.matches.contains { $0.vars.contains { $0.type == "shell" } }
                let path = url.path
                loaded.append(LoadedEspansoFile(
                    id: path, url: url, matchFile: matchFile,
                    containsShellVars: hasShell, isApproved: isFileApproved(path: path, matchFile: matchFile)
                ))
            } catch {
                // One malformed file (hand-edited YAML typo) must not disable
                // every other loaded file — skip and log, keep going.
                storeLog.error("failed to parse \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        espansoFiles = loaded

        // Every file needs one-time review — not just ones with shell vars.
        // A plain static-text match file dropped into the watched directory
        // by anything else with write access there could otherwise silently
        // redefine an existing trigger (e.g. hijack ":mw" to a different
        // email address) with zero visible consent, since only shell
        // execution was originally gated. Text-only files still get a
        // (lighter-worded) one-time prompt; shell files keep the explicit
        // command listing.
        if let firstUnapproved = loaded.first(where: { !$0.isApproved }) {
            pendingFileApproval = firstUnapproved
        }
    }

    /// Stable (cross-launch) hash of the file's full match content —
    /// triggers, replacement text, and vars together, not just shell
    /// commands. Deliberately SHA256, not Swift's `String.hashValue` — that
    /// hash is randomized per process for hash-flooding protection, so it
    /// would silently re-prompt (or worse, never match) on every single app
    /// restart. Approval is tied to *this exact content*: if the file
    /// changes later (edited, or overwritten by a sync), the hash changes
    /// and the review prompt reappears — a file can't be silently altered
    /// after being approved once, whether that alteration adds a shell
    /// command or just changes what a plain trigger expands to.
    private func fileContentHash(_ matchFile: EspansoMatchFile) -> String {
        let description = matchFile.matches
            .map { match -> String in
                let varsDescription = match.vars
                    .map { "\($0.name)|\($0.type)|\($0.params.cmd ?? "")|\($0.params.format ?? "")" }
                    .joined(separator: ";")
                return "\(match.triggers.joined(separator: ","))|\(match.replace)|\(varsDescription)"
            }
            .sorted()
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(description.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isFileApproved(path: String, matchFile: EspansoMatchFile) -> Bool {
        defaults.string(forKey: Keys.approvedHashKey(path: path)) == fileContentHash(matchFile)
    }

    func approveFile(_ file: LoadedEspansoFile) {
        defaults.set(fileContentHash(file.matchFile), forKey: Keys.approvedHashKey(path: file.id))
        if pendingFileApproval?.id == file.id { pendingFileApproval = nil }
        reloadEspansoFiles()
    }

    /// Declining doesn't delete anything — that one file's matches simply
    /// stay inactive (see `activeTriggers()`/`action(forTrigger:)`) until
    /// approved from Settings later.
    func declineFile(_ file: LoadedEspansoFile) {
        if pendingFileApproval?.id == file.id { pendingFileApproval = nil }
    }

    // MARK: - Lookup used by the keystroke monitor

    func activeTriggers() -> [String] {
        guard isEnabled else { return [] }
        var triggers = appSnippets.map(\.trigger)
        for file in espansoFiles where file.isApproved {
            for match in file.matchFile.matches {
                triggers.append(contentsOf: match.triggers)
            }
        }
        return triggers
    }

    func action(forTrigger trigger: String) -> SnippetAction? {
        if let snippet = appSnippets.first(where: { $0.trigger == trigger }) {
            guard !snippet.vars.isEmpty else { return .staticText(snippet.replacement) }
            // Dynamic app-created snippet (built via "Insert Variable", not
            // hand-typed shell) — same resolver as Espanso imports, since
            // `SnippetMatch` is just a generic (trigger, template, vars)
            // carrier, not something inherently tied to Espanso's file format.
            return .espansoMatch(SnippetMatch(triggers: [snippet.trigger], replace: snippet.replacement, vars: snippet.vars))
        }
        for file in espansoFiles where file.isApproved {
            if let match = file.matchFile.matches.first(where: { $0.triggers.contains(trigger) }) {
                return .espansoMatch(match)
            }
        }
        return nil
    }

    /// Shell-var resolution shells out and blocks on process exit — run off
    /// the main actor so a slow/hanging command never freezes the UI thread.
    nonisolated func resolve(_ action: SnippetAction) async -> String {
        switch action {
        case .staticText(let text):
            return text
        case .espansoMatch(let match):
            return await Task.detached(priority: .userInitiated) {
                SnippetVariableResolver.resolve(match)
            }.value
        }
    }
}
