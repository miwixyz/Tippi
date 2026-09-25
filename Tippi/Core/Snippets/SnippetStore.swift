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

/// One Espanso match file found in the watched directory — an import
/// candidate, nothing more. Its triggers are never live until imported.
/// `containsShellVars` only drives what the list shows.
struct LoadedEspansoFile: Identifiable, Equatable {
    let id: String // file path — stable across reloads
    let url: URL
    var matchFile: EspansoMatchFile
    var containsShellVars: Bool
}

/// Owns two snippet sources and merges them into the single trigger→action
/// lookup the keystroke monitor needs:
/// - app-managed (JSON, full CRUD in Settings)
/// - imported Espanso snippets (copied into Tippi's own store, gated
///   per-snippet — see `importFile` and docs/SECURE-DESIGN-espanso-import.md)
///
/// Espanso files found in the watched directory are listed as import
/// candidates only. They are never executed in place.
///
/// Reading them live used to be a third source, gated by a SHA256 of the file
/// contents kept in UserDefaults. Removed 2026-09-15: that anchor held no
/// secret and lived in a file any process running as the user can write, so an
/// attacker could compute the hash of their own match file and store it — the
/// approval prompt never appeared and the commands ran. Reproduced during the
/// pre-release audit against two real approvals. Import already replaces
/// reference (Michael's call the same morning) and protects consent with a
/// Keychain-held MAC instead, so the weaker path had a successor and simply
/// went away rather than being hardened.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var appSnippets: [AppSnippet] = []
    @Published private(set) var espansoFiles: [LoadedEspansoFile] = []
    /// Snippets copied out of Espanso files via `importFile`. Once a file is
    /// imported it disappears from `espansoFiles` entirely — import replaces
    /// the live reference for that file, it doesn't sit alongside it (see
    /// docs/SECURE-DESIGN-espanso-import.md and Michael's 2026-09-15 call:
    /// import supersedes reference, not a parallel mode).
    @Published private(set) var importedSnippets: [ImportedSnippet] = []

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

    /// One imported snippet at a time awaiting its per-snippet shell-command
    /// consent decision. One at a time on purpose: the prompt then always
    /// names one concrete command, never a batch.
    ///
    /// Clearing `approvalError` here rather than at each call site covers every
    /// way the sheet can change hands. A failed signature left the message set
    /// forever: declining closed the sheet but kept it, and tapping a *different*
    /// snippet's badge later re-opened the sheet already showing a red error
    /// that belonged to another snippet and predated any click.
    @Published var pendingShellApproval: ImportedSnippet? {
        didSet {
            if pendingShellApproval?.id != oldValue?.id { approvalError = nil }
        }
    }

    private enum Keys {
        static let enabled = "tippi.snippets.enabled.v1"
        static let prefix = "tippi.snippets.prefix.v1"
        static let matchDir = "tippi.snippets.matchDir.v1"
        static let appSnippetsFile = "AppSnippets.json"
        static let importedSnippetsFile = "ImportedSnippets.json"
        static let importedFilePaths = "tippi.snippets.importedFilePaths.v1"
        /// Legacy prefix from the removed reference-approval path. Only used
        /// to clean stale entries out of UserDefaults on launch.
        static let legacyApprovedHashPrefix = "tippi.snippets.approvedShellHash."
    }

    private let fileManager = FileManager.default
    /// Injected so unit tests can point persistence at a temp directory and
    /// an ephemeral defaults suite instead of writing into Michael's real
    /// `~/Library/Application Support/Tippi` and the app's real UserDefaults
    /// domain. Production always uses the defaults (nil / `.standard`).
    private let appSupportRoot: URL
    private let defaults: UserDefaults
    /// Resolved paths of Espanso files already imported — kept out of
    /// `espansoFiles`/reference-approval entirely once here (see
    /// `reloadEspansoFiles`). Persisted so a re-import doesn't resurrect the
    /// file as a "new" reference after a relaunch.
    private var importedFilePaths: Set<String>
    /// Keychain service used for shell-snippet approval signing/verification.
    /// Injected for the same reason `appSupportRoot`/`userDefaults` are:
    /// tests must never sign or verify against `SnippetApprovalSigner`'s
    /// real production service, or a test run revoking/creating keys there
    /// would touch Michael's actual Keychain state on the machine running
    /// the tests.
    private let keychainService: String

    init(appSupportRoot: URL? = nil, userDefaults: UserDefaults = .standard, keychainService: String = SnippetApprovalSigner.defaultService) {
        self.appSupportRoot = appSupportRoot ?? Self.systemAppSupportDirectory
        self.defaults = userDefaults
        self.keychainService = keychainService
        self.isEnabled = userDefaults.bool(forKey: Keys.enabled)
        self.defaultPrefix = userDefaults.string(forKey: Keys.prefix) ?? ":"
        self.importedFilePaths = Set(userDefaults.stringArray(forKey: Keys.importedFilePaths) ?? [])
        if let saved = userDefaults.string(forKey: Keys.matchDir) {
            self.matchDirectory = URL(fileURLWithPath: saved)
        } else {
            self.matchDirectory = (appSupportRoot ?? Self.systemAppSupportDirectory)
                .appendingPathComponent("espanso/match", isDirectory: true)
        }
        loadAppSnippets()
        loadImportedSnippets()
        removeLegacyApprovalHashes()
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

    /// Set when the snippet file exists but could not be read or decoded.
    /// Blocks saving, because an empty in-memory list must never be written
    /// over a file whose contents we simply failed to parse.
    @Published private(set) var appSnippetsLoadError: String?

    private func loadAppSnippets() {
        // "File is absent" and "file is unreadable" are different situations
        // and used to collapse into the same empty list. That turned a parse
        // failure into permanent data loss: the list came up empty with no
        // message, the user re-created a snippet, and the next save wrote the
        // empty array over everything that was still on disk.
        guard FileManager.default.fileExists(atPath: appSnippetsURL.path) else {
            appSnippets = []
            appSnippetsLoadError = nil
            return
        }
        do {
            let data = try Data(contentsOf: appSnippetsURL)
            let decoded = try JSONDecoder().decode([AppSnippet].self, from: data)
            // Snippets written by Tippi 2.3.0 and earlier spell their weekday
            // commands without the locale prefix. The expansion guard only
            // accepts commands the current builder could emit, so without this
            // they would go quiet on update: the trigger stops expanding, the
            // snippet still looks fine in Settings, and the only trace is a log
            // line accusing the user of editing the file by hand — which Tippi
            // itself wrote that way.
            let (migrated, didMigrate) = Self.migratingLegacyCommands(decoded)
            appSnippets = migrated
            appSnippetsLoadError = nil
            if didMigrate {
                storeLog.info("migrated legacy dynamic-variable commands to the current spelling")
                saveAppSnippets()
            }
        } catch {
            // Keep the file, keep the list empty, and refuse to save until the
            // user has dealt with it. A copy is put aside so the contents stay
            // recoverable by hand even if something later overwrites the file.
            appSnippets = []
            appSnippetsLoadError = error.localizedDescription
            storeLog.error("could not read \(Keys.appSnippetsFile, privacy: .public): \(error.localizedDescription, privacy: .public) — saving is disabled until this is resolved")
            let backup = appSnippetsURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.copyItem(at: appSnippetsURL, to: backup)
        }
    }

    /// Rewrites only those shell commands an older Tippi generated and the
    /// current builder spells differently. Anything the builder would not emit
    /// either way is left exactly as found — migration can never turn a command
    /// that was refused into one that runs unless the current builder produces
    /// that identical command itself.
    private static func migratingLegacyCommands(_ snippets: [AppSnippet]) -> ([AppSnippet], Bool) {
        var didMigrate = false
        let migrated = snippets.map { snippet -> AppSnippet in
            guard snippet.vars.contains(where: { $0.type == "shell" }) else { return snippet }
            var copy = snippet
            copy.vars = snippet.vars.map { variable in
                guard variable.type == "shell",
                      let cmd = variable.params.cmd,
                      let upgraded = DynamicVariableBuilder.migratedCommand(cmd)
                else { return variable }
                didMigrate = true
                return SnippetVar(
                    name: variable.name,
                    type: variable.type,
                    params: SnippetVarParams(cmd: upgraded, format: variable.params.format)
                )
            }
            return copy
        }
        return (migrated, didMigrate)
    }

    /// Re-reads the snippet file, clearing the save block if the problem was
    /// fixed outside the app.
    ///
    /// The block has to be escapable. Without this the only exit was relaunching
    /// Tippi, and the intervening session was quietly lossy: the list happily
    /// accepted new snippets, none of them reached disk, and they were gone
    /// after the restart. The remedy for the corrupt file itself lives outside
    /// the app (repair or delete it), so the app needs a way to notice.
    func reloadAppSnippets() {
        loadAppSnippets()
    }

    private func saveAppSnippets() {
        // Re-check rather than trusting the flag from launch: if the unreadable
        // file has since been deleted there is nothing left to protect, and
        // refusing forever would strand every snippet created after that.
        if appSnippetsLoadError != nil,
           !FileManager.default.fileExists(atPath: appSnippetsURL.path) {
            storeLog.info("the unreadable snippet file is gone — lifting the save block")
            appSnippetsLoadError = nil
        }
        guard appSnippetsLoadError == nil else {
            storeLog.error("refusing to save app snippets: the existing file could not be read, writing now would destroy it")
            return
        }
        guard let data = try? JSONEncoder().encode(appSnippets) else { return }
        try? data.write(to: appSnippetsURL, options: .atomic)
    }

    /// True while the snippet file could not be read. Mutating the list is
    /// refused in that state rather than accepted and dropped — the UI showed
    /// success for writes that never happened.
    private var appSnippetEditsAreBlocked: Bool {
        guard appSnippetsLoadError != nil else { return false }
        // A deleted file clears the block; `saveAppSnippets` does the same check
        // and would accept the write, so refusing here would contradict it.
        return FileManager.default.fileExists(atPath: appSnippetsURL.path)
    }

    /// Prepends `defaultPrefix` only for a bare word (e.g. "mlg" → ":mlg").
    /// A shortcut that already starts with punctuation — any punctuation,
    /// not just the configured prefix — is treated as a deliberately
    /// complete trigger and left untouched, so a one-off different prefix
    /// (";foo", "##bar") still works by just typing it in full.
    func addSnippet(shortcut: String, replacement: String, vars: [SnippetVar] = []) {
        guard !appSnippetEditsAreBlocked else { return }
        let trimmed = shortcut.trimmingCharacters(in: .whitespaces)
        let looksLikeACompleteTrigger = trimmed.first.map { !$0.isLetter && !$0.isNumber } ?? true
        let trigger = looksLikeACompleteTrigger ? trimmed : defaultPrefix + trimmed
        appSnippets.append(AppSnippet(trigger: trigger, replacement: replacement, vars: vars))
        saveAppSnippets()
    }

    func updateSnippet(_ snippet: AppSnippet) {
        guard !appSnippetEditsAreBlocked else { return }
        guard let idx = appSnippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        appSnippets[idx] = snippet
        saveAppSnippets()
    }

    func removeSnippet(_ snippet: AppSnippet) {
        guard !appSnippetEditsAreBlocked else { return }
        appSnippets.removeAll { $0.id == snippet.id }
        saveAppSnippets()
    }

    // MARK: - Espanso files in the watched directory (import candidates only)

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
            // Already imported → import replaces reference for this file
            // (2026-09-15 decision). It must not reappear here asking for a
            // reference-approval that would immediately become irrelevant.
            guard !importedFilePaths.contains(url.path) else { continue }
            do {
                let matchFile = try EspansoYAMLParser.parseFile(at: url)
                let hasShell = matchFile.matches.contains { $0.vars.contains { $0.type == "shell" } }
                let path = url.path
                loaded.append(LoadedEspansoFile(
                    id: path, url: url, matchFile: matchFile,
                    containsShellVars: hasShell
                ))
            } catch {
                // One malformed file (hand-edited YAML typo) must not disable
                // every other loaded file — skip and log, keep going.
                storeLog.error("failed to parse \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        espansoFiles = loaded
    }

    /// Drops the UserDefaults entries left behind by the removed
    /// reference-approval path. They no longer mean anything, and leaving
    /// forged-approval material lying around in a file an attacker can write
    /// would be an odd way to retire a mechanism because it was forgeable.
    private func removeLegacyApprovalHashes() {
        let stale = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Keys.legacyApprovedHashPrefix) }
        guard !stale.isEmpty else { return }
        stale.forEach { defaults.removeObject(forKey: $0) }
        storeLog.notice("removed \(stale.count, privacy: .public) obsolete reference-approval entries")
    }

    // MARK: - Espanso import (replaces the reference for that file)

    private var importedSnippetsURL: URL {
        tippiSupportDirectory.appendingPathComponent(Keys.importedSnippetsFile)
    }

    /// Set when the imported-snippet file exists but could not be read.
    /// Same contract as `appSnippetsLoadError`, and for the same reason: this
    /// file carries the shell approvals, so overwriting an unparsed one costs
    /// the user every consent decision they have made.
    @Published private(set) var importedSnippetsLoadError: String?

    private func loadImportedSnippets() {
        // The `try?`-collapse this replaces treated "file absent" and "file
        // unreadable" alike. A half-written file (crash mid-save, a sync
        // conflict) came up as an empty list with no message, and the next
        // import wrote that single entry over everything else — approvals
        // included.
        guard FileManager.default.fileExists(atPath: importedSnippetsURL.path) else {
            importedSnippets = []
            importedSnippetsLoadError = nil
            return
        }
        do {
            let data = try Data(contentsOf: importedSnippetsURL)
            importedSnippets = try JSONDecoder().decode([ImportedSnippet].self, from: data)
            importedSnippetsLoadError = nil
        } catch {
            importedSnippets = []
            importedSnippetsLoadError = error.localizedDescription
            storeLog.error("could not read \(Keys.importedSnippetsFile, privacy: .public): \(error.localizedDescription, privacy: .public) — saving is disabled until this is resolved")
            let backup = importedSnippetsURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.copyItem(at: importedSnippetsURL, to: backup)
        }
    }

    /// Re-reads the imported-snippet file, lifting the save block if the file
    /// was repaired outside the app.
    func reloadImportedSnippets() {
        loadImportedSnippets()
    }

    private func saveImportedSnippets() {
        if importedSnippetsLoadError != nil,
           !FileManager.default.fileExists(atPath: importedSnippetsURL.path) {
            storeLog.info("the unreadable imported-snippet file is gone — lifting the save block")
            importedSnippetsLoadError = nil
        }
        guard importedSnippetsLoadError == nil else {
            storeLog.error("refusing to save imported snippets: the existing file could not be read, writing now would destroy it")
            return
        }
        guard let data = try? JSONEncoder().encode(importedSnippets) else { return }
        try? data.write(to: importedSnippetsURL, options: .atomic)
    }

    private func saveImportedFilePaths() {
        defaults.set(Array(importedFilePaths), forKey: Keys.importedFilePaths)
    }

    /// Copies every match in `file` into `importedSnippets`, then removes the
    /// file from live reference (`reloadEspansoFiles` will skip it from now
    /// on). Every matching-by-trigger case is deliberate, not an oversight:
    ///
    /// - Unseen trigger → new entry. Plain text/date-only is active
    ///   immediately (no execution surface, nothing to consent to). A
    ///   shell-bearing one starts with `shellApproval == nil` regardless of
    ///   whether the *file* was ever approved for reference — that approval
    ///   was for continuous file-hash verification, a different trust model,
    ///   and does not transfer (docs/SECURE-DESIGN-espanso-import.md,
    ///   "Migration — ask once").
    /// - Existing trigger, byte-identical content → left untouched,
    ///   preserving any approval it already has. Re-running an import must be
    ///   idempotent, not a re-prompt machine.
    /// - Existing trigger, content changed → replaced with a fresh unapproved
    ///   entry. "Matching by trigger is not sufficient to inherit approval"
    ///   is the one rule this whole feature exists to enforce; re-import is
    ///   the exact laundering path the design doc calls out.
    func importFile(_ file: LoadedEspansoFile) {
        // First-wins inside one file, matching how the reference path resolves
        // it (`matches.first(where:)` in `action(forTrigger:)`). The previous
        // last-wins behaviour meant a file containing the same trigger twice
        // expanded to one thing while referenced and to the other after being
        // imported — the meaning of a snippet changed through an action sold as
        // a change of storage location.
        var seenInThisFile = Set<String>()
        for match in file.matchFile.matches {
            let candidate = ImportedSnippet(
                triggers: match.triggers, replace: match.replace,
                vars: match.vars, sourcePath: file.id
            )
            guard seenInThisFile.insert(candidate.trigger).inserted else {
                storeLog.error("\(file.url.lastPathComponent, privacy: .public) defines '\(candidate.trigger, privacy: .public)' more than once — keeping the first, as the referenced path does")
                continue
            }
            // Matched per source file, not globally: Espanso allows two files
            // to define the same trigger, and silently overwriting one with the
            // other loses a snippet the user never asked to remove.
            if let idx = importedSnippets.firstIndex(where: { $0.trigger == candidate.trigger && $0.sourcePath == file.id }) {
                let existing = importedSnippets[idx]
                if existing.replace != candidate.replace || existing.vars != candidate.vars || existing.triggers != candidate.triggers {
                    importedSnippets[idx] = candidate
                }
            } else {
                importedSnippets.append(candidate)
            }
        }
        importedFilePaths.insert(file.id)
        saveImportedSnippets()
        saveImportedFilePaths()
        reloadEspansoFiles()
        refreshPendingShellApproval()
    }

    /// Signs the snippet's current (trigger, shell-command) pair and stores
    /// the resulting MAC. Fails closed and visibly: no Keychain key means no
    /// approval is recorded, not a silent no-op that looks like success.
    /// Set when signing an approval failed. Surfaced in the consent sheet —
    /// the previous version only wrote to the log while the sheet closed as if
    /// the approval had been granted, so the user saw the badge stay orange
    /// with no explanation and clicking again did nothing visible either.
    @Published var approvalError: String?

    func approveShellSnippet(_ snippet: ImportedSnippet) {
        guard let idx = importedSnippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        guard let approval = SnippetApprovalSigner.sign(trigger: snippet.trigger,
                                                        command: snippet.shellCommandDigest,
                                                        service: keychainService) else {
            storeLog.error("could not sign shell snippet approval — Keychain key unavailable")
            approvalError = String(localized: "settings.snippets.approvalFailed")
            return
        }
        approvalError = nil
        importedSnippets[idx].shellApproval = approval
        saveImportedSnippets()
        if pendingShellApproval?.id == snippet.id { pendingShellApproval = nil }
        refreshPendingShellApproval()
    }

    /// Declining doesn't delete the snippet — it just stays inactive (not
    /// matched, not expandable) until approved later from Settings.
    ///
    /// Deliberately does *not* call
    /// `refreshPendingShellApproval()`: that method's criterion (has shell
    /// vars, not yet approved) is still true for the just-declined snippet,
    /// so an auto-advance here would immediately re-select and re-show the
    /// very consent sheet the user just dismissed. The next pending item (if
    /// any) surfaces on the next import or when tapped explicitly.
    func declineShellSnippet(_ snippet: ImportedSnippet) {
        if pendingShellApproval?.id == snippet.id { pendingShellApproval = nil }
    }

    func removeImportedSnippet(_ snippet: ImportedSnippet) {
        importedSnippets.removeAll { $0.id == snippet.id }
        saveImportedSnippets()
        if pendingShellApproval?.id == snippet.id { pendingShellApproval = nil }

        // Release the source file once nothing from it remains, so it shows up
        // as a referenced file again. Without this, import was a one-way door:
        // deleting the snippets left the file skipped forever by
        // `reloadEspansoFiles`, present in neither list, recoverable only by
        // editing UserDefaults or renaming the file on disk.
        guard let source = snippet.sourcePath,
              !importedSnippets.contains(where: { $0.sourcePath == source })
        else { return }
        importedFilePaths.remove(source)
        saveImportedFilePaths()
        reloadEspansoFiles()
    }

    /// Whether an app-managed snippet may expand at all.
    ///
    /// Only shell vars are gated, and only on whether `DynamicVariableBuilder`
    /// could have emitted that exact command. Anything else in the file is
    /// inert text. A non-match means the JSON was written outside Tippi's own
    /// code path, so it fails closed and says so — a snippet that silently
    /// stops working is a far better outcome than one that silently runs
    /// somebody else's command.
    private func isAppSnippetSafeToExpand(_ snippet: AppSnippet) -> Bool {
        for variable in snippet.vars where variable.type == "shell" {
            guard DynamicVariableBuilder.canGenerate(variable.params.cmd ?? "") else {
                storeLog.error("refusing app snippet '\(snippet.trigger, privacy: .public)': shell command is not one Tippi generates — AppSnippets.json was modified outside the app")
                return false
            }
        }
        return true
    }

    /// True for plain/date-only imported snippets (no consent needed at
    /// all), and for shell-bearing ones only once `verify` — not just the
    /// presence of a stored MAC — succeeds against the *current* trigger and
    /// command. Called from both `activeTriggers()` and `action(forTrigger:)`
    /// on every lookup, not cached at import/load time: that's what makes
    /// this the "verified immediately before execution" property the design
    /// doc requires, matching how `espansoFiles`' file-hash check already
    /// works today.
    /// Exposed so the Settings badge can ask the same question expansion asks,
    /// instead of approximating it with "a MAC is stored".
    func isImportedSnippetActive(_ snippet: ImportedSnippet) -> Bool {
        isSnippetActive(snippet)
    }

    private func isSnippetActive(_ snippet: ImportedSnippet) -> Bool {
        guard snippet.hasShellVars else { return true }
        return SnippetApprovalSigner.verify(snippet.shellApproval, trigger: snippet.trigger,
                                            command: snippet.shellCommandDigest, service: keychainService)
    }

    /// Advances `pendingShellApproval` to the next snippet that still needs a
    /// decision, or clears it. Called after any mutation that could change
    /// the queue (import, approve, decline) so the consent sheet always shows
    /// something real or nothing at all — never a stale entry.
    private func refreshPendingShellApproval() {
        pendingShellApproval = importedSnippets.first { $0.hasShellVars && !isSnippetActive($0) }
    }

    // MARK: - Lookup used by the keystroke monitor

    func activeTriggers() -> [String] {
        guard isEnabled else { return [] }
        var triggers = appSnippets.filter(isAppSnippetSafeToExpand).map(\.trigger)
        for snippet in importedSnippets where isSnippetActive(snippet) {
            triggers.append(contentsOf: snippet.triggers)
        }
        return triggers
    }

    func action(forTrigger trigger: String) -> SnippetAction? {
        if let snippet = appSnippets.first(where: { $0.trigger == trigger }) {
            // AppSnippets.json is unsigned and writable by any process running
            // as the user, so a `type: shell` var found here would otherwise
            // execute with full privileges the moment its trigger is typed —
            // the same threat docs/SECURE-DESIGN-espanso-import.md closes for
            // imported snippets.
            //
            // The question is NOT "does this have a shell var" — the Insert
            // Variable picker legitimately produces them, because date and
            // weekday variables need a shell for the `LC_TIME=…` locale
            // override. A blanket refusal was tried on 2026-09-15 and broke
            // every date snippet. The question is whether Tippi itself could
            // have written this exact command.
            guard isAppSnippetSafeToExpand(snippet) else { return nil }
            guard !snippet.vars.isEmpty else { return .staticText(snippet.replacement) }
            // Dynamic app-created snippet (built via "Insert Variable", not
            // hand-typed shell) — same resolver as Espanso imports, since
            // `SnippetMatch` is just a generic (trigger, template, vars)
            // carrier, not something inherently tied to Espanso's file format.
            return .espansoMatch(SnippetMatch(triggers: [snippet.trigger], replace: snippet.replacement, vars: snippet.vars))
        }
        // Re-checks `isSnippetActive` here too, not just in `activeTriggers()`
        // — this is the actual gate the design doc means by "verified
        // immediately before execution". A snippet whose approval was
        // revoked (or was never valid) between the keystroke monitor reading
        // `activeTriggers()` and the trigger completing must not expand.
        if let snippet = importedSnippets.first(where: { isSnippetActive($0) && $0.triggers.contains(trigger) }) {
            return .espansoMatch(SnippetMatch(triggers: snippet.triggers, replace: snippet.replace, vars: snippet.vars))
        }
        return nil
    }

    /// The triggers of `snippet` that a different imported snippet actually
    /// wins, i.e. typing them expands the other one.
    ///
    /// Two imported files may legitimately define the same trigger — Espanso
    /// allows it and resolves by file precedence. Tippi has no such rule: the
    /// winner is whichever entry comes first in `importedSnippets`, which is
    /// the order they were imported in. That is stable once written, but it is
    /// arbitrary, and nothing in the UI used to reveal that a second definition
    /// was being ignored — two near-identical rows, no indication which one was
    /// live, and deleting "the wrong one" was guesswork.
    ///
    /// Mirrors `action(forTrigger:)` exactly, including that only *active*
    /// snippets can win: an unapproved shell snippet sitting earlier in the
    /// list does not shadow an approved one behind it.
    func shadowedTriggers(of snippet: ImportedSnippet) -> [String] {
        // An inactive snippet is not shadowed, it is simply not approved yet —
        // a different cause, with its own badge, and one that reverses on
        // approval: once approved it sits earlier in the list and wins. Marking
        // it "overridden" would state the opposite of what happens next.
        guard isSnippetActive(snippet) else { return [] }
        return snippet.triggers.filter { trigger in
            guard let winner = importedSnippets.first(where: {
                isSnippetActive($0) && $0.triggers.contains(trigger)
            }) else { return false }
            return winner.id != snippet.id
        }
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
