import XCTest
@testable import Tippi

/// Exercises the per-file consent gate end-to-end against real files in a
/// temp directory — the part of `SnippetStore` most likely to regress
/// silently (see `SnippetStore.fileContentHash`'s comment on why
/// `String.hashValue` would have been a cross-launch-breaking bug).
@MainActor
final class SnippetStoreTests: XCTestCase {
    private var tempDir: URL!
    private var keychainService: String!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Throwaway per-test service — see SnippetApprovalTests for why this
        // must never be the real `SnippetApprovalSigner.defaultService`.
        keychainService = "com.tippi.app.test.snippet-approval.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        SnippetApprovalSigner.revokeAllApprovals(service: keychainService)
    }

    /// Every store in this file is fully isolated from Michael's real
    /// Tippi installation: a fresh temp directory for file persistence
    /// (AppSnippets.json) and a throwaway UserDefaults suite (never
    /// `.standard`) for settings/approval-hash storage, and a throwaway
    /// Keychain service for shell-snippet approval signing.
    private func makeStore() -> SnippetStore {
        let suiteName = "TippiTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SnippetStore(appSupportRoot: tempDir, userDefaults: defaults, keychainService: keychainService)
    }

    private func writeMatchFile(named name: String, shellCmd: String) throws -> URL {
        let yaml = """
        matches:
          - trigger: ":t"
            replace: "{{x}}"
            vars:
              - name: x
                type: shell
                params:
                  cmd: "\(shellCmd)"
        """
        let url = tempDir.appendingPathComponent(name)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testFileWithShellVarsStartsUnapprovedAndInactive() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        XCTAssertEqual(store.espansoFiles.count, 1)
        XCTAssertFalse(store.espansoFiles[0].isApproved)
        XCTAssertNotNil(store.pendingFileApproval)
        // Inactive until approved — must not be reachable by the keystroke
        // monitor before the user has seen the consent prompt.
        XCTAssertFalse(store.activeTriggers().contains(":t"))
        XCTAssertNil(store.action(forTrigger: ":t"))
    }

    func testApprovalPersistsAcrossReload() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        guard let file = store.espansoFiles.first else { return XCTFail("expected one loaded file") }
        store.approveFile(file)

        XCTAssertTrue(store.espansoFiles[0].isApproved)
        XCTAssertTrue(store.activeTriggers().contains(":t"))

        // Simulate a fresh app launch reading the same UserDefaults-backed
        // approval — this is exactly the case a randomized-per-process hash
        // (Swift's `String.hashValue`) would have broken.
        store.reloadEspansoFiles()
        XCTAssertTrue(store.espansoFiles[0].isApproved, "approval must survive a reload, not just the in-memory session")
    }

    func testChangingApprovedCommandRevokesApproval() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        store.approveFile(store.espansoFiles[0])
        XCTAssertTrue(store.espansoFiles[0].isApproved)

        // Overwrite the same file with a different shell command — approval
        // was for the old command set, not for "this file path forever".
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo something-else")
        store.reloadEspansoFiles()

        XCTAssertFalse(store.espansoFiles[0].isApproved, "a changed shell command must re-trigger the consent gate")
        XCTAssertNotNil(store.pendingFileApproval)
    }

    /// A plain text-only match file is NOT exempt from the consent gate —
    /// only the *wording* of the prompt differs (no scary shell-commands
    /// list). Gating only `type: shell` would leave a real hole: anything
    /// with write access to the watched directory could silently redefine
    /// an existing trigger (e.g. hijack ":mw") with zero visible consent.
    func testFileWithoutShellVarsStillNeedsApprovalWithPlainWording() throws {
        let yaml = """
        matches:
          - trigger: ":plain"
            replace: "just text"
        """
        try yaml.write(to: tempDir.appendingPathComponent("plain.yml"), atomically: true, encoding: .utf8)
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        XCTAssertFalse(store.espansoFiles[0].isApproved, "text-only files must still gate on first sight")
        XCTAssertFalse(store.espansoFiles[0].containsShellVars, "flag distinguishes prompt wording only, not whether approval is required")
        XCTAssertNotNil(store.pendingFileApproval)
        XCTAssertFalse(store.activeTriggers().contains(":plain"))

        store.approveFile(store.espansoFiles[0])
        XCTAssertTrue(store.activeTriggers().contains(":plain"))
    }

    func testDisabledStoreHasNoActiveTriggers() throws {
        let yaml = """
        matches:
          - trigger: ":plain"
            replace: "just text"
        """
        try yaml.write(to: tempDir.appendingPathComponent("plain.yml"), atomically: true, encoding: .utf8)
        let store = makeStore()
        store.isEnabled = false
        store.matchDirectory = tempDir

        XCTAssertTrue(store.activeTriggers().isEmpty)
    }

    func testAppSnippetPrefixIsAppliedWhenMissing() {
        let store = makeStore()
        store.matchDirectory = tempDir // empty dir, isolates this test from any real Espanso install
        store.defaultPrefix = ":"
        store.addSnippet(shortcut: "mlg", replacement: "Liebe Grüße")
        XCTAssertEqual(store.appSnippets.last?.trigger, ":mlg")

        store.addSnippet(shortcut: ";already", replacement: "x")
        XCTAssertEqual(store.appSnippets.last?.trigger, ";already", "a shortcut that already starts with a (different) prefix must not get double-prefixed")
    }

    /// Regression test for a real bug found on 2026-09-09: Espanso's actual
    /// default macOS config path (`~/Library/Application Support/espanso/match`)
    /// is routinely a symlink into wherever the user actually keeps their
    /// match files (a dotfiles repo, a synced vault, ...) — exactly the setup
    /// here. `FileManager.contentsOfDirectory(at:)` throws ENOTDIR on a
    /// symlinked directory even though `fileExists` correctly reports it as
    /// one; the fix resolves symlinks before listing. Without this test,
    /// the only non-symlinked directory case (every other test in this file)
    /// would keep passing while the real-world default setup stayed broken.
    func testLoadsFilesThroughASymlinkedMatchDirectory() throws {
        let realDir = tempDir.appendingPathComponent("real-match-target")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let yaml = """
        matches:
          - trigger: ":viaSymlink"
            replace: "it worked"
        """
        try yaml.write(to: realDir.appendingPathComponent("a.yml"), atomically: true, encoding: .utf8)

        let symlinkDir = tempDir.appendingPathComponent("match")
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: realDir)

        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = symlinkDir

        XCTAssertEqual(store.espansoFiles.count, 1, "must list the file through the symlink, not silently return empty")
        store.approveFile(store.espansoFiles[0])
        XCTAssertTrue(store.activeTriggers().contains(":viaSymlink"))
    }

    func testAppSnippetWithDynamicVariableResolvesLive() {
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        let variable = DynamicVariableBuilder.makeVar(name: "y", kind: .today(format: .year))
        store.addSnippet(shortcut: ":year", replacement: "{{y}}", vars: [variable])

        guard let action = store.action(forTrigger: ":year") else { return XCTFail("expected an action for :year") }
        // Must NOT be the plain static path — it has vars, so it needs
        // resolving, not verbatim insertion of the literal "{{y}}" text.
        if case .staticText = action {
            XCTFail("a snippet with vars must not resolve as static text")
        }
    }

    /// A snippet saved by an older build (before `vars` existed) has no
    /// `vars` key in its JSON at all — must still decode, not crash the
    /// whole app-snippets load.
    func testOldPersistedSnippetWithoutVarsKeyStillDecodes() throws {
        let store = makeStore()
        store.matchDirectory = tempDir
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","trigger":":old","replacement":"still works"}]
        """
        let appSupportDir = tempDir.appendingPathComponent("Tippi", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try legacyJSON.write(to: appSupportDir.appendingPathComponent("AppSnippets.json"), atomically: true, encoding: .utf8)

        let reloaded = SnippetStore(appSupportRoot: tempDir, userDefaults: UserDefaults(suiteName: "TippiTests.\(UUID().uuidString)")!)
        XCTAssertEqual(reloaded.appSnippets.first?.trigger, ":old")
        XCTAssertEqual(reloaded.appSnippets.first?.vars, [])
    }

    func testMalformedFileIsSkippedWithoutBreakingOthers() throws {
        try "not: [valid yaml structure".write(to: tempDir.appendingPathComponent("broken.yml"), atomically: true, encoding: .utf8)
        let yaml = """
        matches:
          - trigger: ":ok"
            replace: "fine"
        """
        try yaml.write(to: tempDir.appendingPathComponent("ok.yml"), atomically: true, encoding: .utf8)

        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        XCTAssertEqual(store.espansoFiles.count, 1, "the broken file must be skipped, not crash the whole load")
        store.approveFile(store.espansoFiles[0])
        XCTAssertTrue(store.activeTriggers().contains(":ok"))
    }

    // MARK: - Import (docs/SECURE-DESIGN-espanso-import.md)

    /// Plain-text imports need no consent at all — the whole point of
    /// splitting by risk instead of gating everything like a shell snippet.
    func testImportingPlainFileActivatesImmediatelyAndReplacesReference() throws {
        let yaml = """
        matches:
          - trigger: ":plain"
            replace: "just text"
        """
        try yaml.write(to: tempDir.appendingPathComponent("plain.yml"), atomically: true, encoding: .utf8)
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        store.importFile(store.espansoFiles[0])

        XCTAssertTrue(store.activeTriggers().contains(":plain"), "no shell vars — must not need consent")
        XCTAssertNil(store.pendingShellApproval)
        XCTAssertTrue(store.espansoFiles.isEmpty, "import replaces reference — the file must not still ask for reference approval")
        XCTAssertEqual(store.importedSnippets.count, 1)
    }

    /// Mirrors `testFileWithShellVarsStartsUnapprovedAndInactive` for the
    /// import path: a shell snippet is inactive until its own per-snippet
    /// consent is given, not the file's.
    func testImportedShellSnippetStartsUnapprovedAndInactive() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        store.importFile(store.espansoFiles[0])

        XCTAssertFalse(store.activeTriggers().contains(":t"))
        XCTAssertNil(store.action(forTrigger: ":t"))
        XCTAssertNotNil(store.pendingShellApproval)
        XCTAssertEqual(store.pendingShellApproval?.trigger, ":t")
    }

    func testApprovingImportedShellSnippetActivatesIt() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        store.importFile(store.espansoFiles[0])

        let snippet = try XCTUnwrap(store.pendingShellApproval)
        store.approveShellSnippet(snippet)

        XCTAssertNil(store.pendingShellApproval)
        XCTAssertTrue(store.activeTriggers().contains(":t"))
        XCTAssertNotNil(store.action(forTrigger: ":t"))
    }

    /// The rule the whole design exists to enforce: matching by trigger is
    /// not enough to inherit an approval. A file whose shell command changed
    /// between imports must arrive unapproved again, even though the old
    /// approval is still sitting in the store under the same trigger.
    func testReimportWithChangedCommandRevokesApproval() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        let sourceID = store.espansoFiles[0].id
        store.importFile(store.espansoFiles[0])
        store.approveShellSnippet(try XCTUnwrap(store.pendingShellApproval))
        XCTAssertTrue(store.activeTriggers().contains(":t"))

        // Re-import the SAME file with a different command, as if the original
        // Espanso file had been edited on disk. Must use the store's own file
        // id: it resolves symlinks (/var → /private/var on macOS), and a
        // different path is a different source file, not a re-import.
        let secondFile = LoadedEspansoFile(
            id: sourceID,
            url: tempDir.appendingPathComponent("a.yml"),
            matchFile: try EspansoYAMLParser.parse("""
            matches:
              - trigger: ":t"
                replace: "{{x}}"
                vars:
                  - name: x
                    type: shell
                    params:
                      cmd: "echo something-else"
            """),
            containsShellVars: true,
            isApproved: false
        )
        store.importFile(secondFile)

        XCTAssertFalse(store.activeTriggers().contains(":t"), "a changed command must not inherit the old approval")
        XCTAssertNotNil(store.pendingShellApproval)
    }

    /// Re-importing byte-identical content must be a no-op for an already
    /// approved snippet, not a fresh unapproved entry — otherwise every
    /// harmless re-scan would silently revoke working approvals.
    func testReimportWithUnchangedContentPreservesApproval() throws {
        let file = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        let sourceID = store.espansoFiles[0].id
        store.importFile(store.espansoFiles[0])
        store.approveShellSnippet(try XCTUnwrap(store.pendingShellApproval))

        let sameFile = LoadedEspansoFile(
            id: sourceID, url: file,
            matchFile: try EspansoYAMLParser.parseFile(at: file),
            containsShellVars: true, isApproved: false
        )
        store.importFile(sameFile)

        XCTAssertTrue(store.activeTriggers().contains(":t"), "identical re-import must not revoke an existing approval")
        XCTAssertNil(store.pendingShellApproval)
    }

    /// Regression test: declining must not immediately re-select the same
    /// snippet again. `refreshPendingShellApproval`'s criterion (has shell
    /// vars, not approved) is still true right after a decline, so calling
    /// it there would re-show the very sheet the user just dismissed.
    func testDecliningShellSnippetDoesNotReprompt() throws {
        _ = try writeMatchFile(named: "a.yml", shellCmd: "echo hi")
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        store.importFile(store.espansoFiles[0])

        let snippet = try XCTUnwrap(store.pendingShellApproval)
        store.declineShellSnippet(snippet)

        XCTAssertNil(store.pendingShellApproval, "declining must clear the prompt, not re-surface the same snippet")
        XCTAssertFalse(store.activeTriggers().contains(":t"), "declined snippet stays inactive, same convention as declineFile")
    }

    // MARK: - Regressions found in the 2026-09-15 pre-release audit

    /// An unreadable file must not look like an empty one, and must never be
    /// overwritten. The silent version of this destroyed the file's contents:
    /// list came up empty, user re-created a snippet, save wrote `[]` over it.
    func testCorruptSnippetFileBlocksSavingInsteadOfOverwritingIt() throws {
        let supportDir = tempDir.appendingPathComponent("Tippi", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let file = supportDir.appendingPathComponent("AppSnippets.json")
        try "{ this is not valid json".write(to: file, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.matchDirectory = tempDir
        XCTAssertTrue(store.appSnippets.isEmpty)
        XCTAssertNotNil(store.appSnippetsLoadError, "a parse failure must be reported, not silently shown as 'no snippets'")

        store.addSnippet(shortcut: ":neu", replacement: "x")
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(onDisk, "{ this is not valid json", "the unreadable file must be left untouched")
    }

    /// Import used to be a one-way door: deleting the snippets left the source
    /// file skipped forever, visible in neither list.
    func testRemovingAllImportedSnippetsReleasesTheSourceFile() throws {
        let yaml = """
        matches:
          - trigger: ":a"
            replace: "A"
        """
        try yaml.write(to: tempDir.appendingPathComponent("a.yml"), atomically: true, encoding: .utf8)
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        store.importFile(store.espansoFiles[0])
        XCTAssertTrue(store.espansoFiles.isEmpty, "imported file leaves the reference list")
        XCTAssertEqual(store.importedSnippets.count, 1)

        store.removeImportedSnippet(store.importedSnippets[0])
        XCTAssertEqual(store.espansoFiles.count, 1, "with nothing imported from it left, the file must be referenceable again")
    }

    /// Same trigger twice in one file resolved differently before and after
    /// importing — the meaning of a snippet changed through an action sold as
    /// a change of storage location. Reference path is first-wins, so import is.
    func testDuplicateTriggerInOneFileKeepsTheFirstJustLikeTheReferencePath() throws {
        let yaml = """
        matches:
          - trigger: ":mw"
            replace: "erste"
          - trigger: ":mw"
            replace: "zweite"
        """
        try yaml.write(to: tempDir.appendingPathComponent("dup.yml"), atomically: true, encoding: .utf8)
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        store.approveFile(store.espansoFiles[0])
        guard case .espansoMatch(let referenced)? = store.action(forTrigger: ":mw") else {
            return XCTFail("expected a match while referenced")
        }
        XCTAssertEqual(referenced.replace, "erste")

        store.importFile(store.espansoFiles[0])
        XCTAssertEqual(store.importedSnippets.count, 1, "the duplicate must not become a second entry")
        XCTAssertEqual(store.importedSnippets[0].replace, "erste", "import must resolve the duplicate the same way the reference path does")
    }

    /// Two files may legitimately define the same trigger (Espanso resolves by
    /// file precedence). Importing the second must not silently delete the first.
    func testSameTriggerInTwoFilesKeepsBothEntries() throws {
        for (name, text) in [("base.yml", "geschaeftlich"), ("local.yml", "privat")] {
            let yaml = """
            matches:
              - trigger: ":mw"
                replace: "\(text)"
            """
            try yaml.write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        while let file = store.espansoFiles.first { store.importFile(file) }
        XCTAssertEqual(store.importedSnippets.count, 2, "one file's snippet must not overwrite the other's")
    }
}
