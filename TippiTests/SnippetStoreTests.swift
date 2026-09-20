import XCTest
@testable import Tippi

/// Exercises import and the per-snippet shell consent end-to-end against real
/// files in a temp directory — the part of `SnippetStore` most likely to
/// regress silently, because every failure mode here is a shortcut that simply
/// stops working rather than anything that announces itself.
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
        suites.removeAll()
    }

    /// Every store in this file is fully isolated from Michael's real
    /// Tippi installation: a fresh temp directory for file persistence
    /// (AppSnippets.json) and a throwaway UserDefaults suite (never
    /// `.standard`) for settings/approval-hash storage, and a throwaway
    /// Keychain service for shell-snippet approval signing.
    private let suites = ThrowawayDefaults()

    private func makeStore() -> SnippetStore {
        SnippetStore(appSupportRoot: tempDir, userDefaults: suites.make(), keychainService: keychainService)
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
        store.importFile(store.espansoFiles[0])
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

        let reloaded = SnippetStore(appSupportRoot: tempDir, userDefaults: suites.make())
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
        store.importFile(store.espansoFiles[0])
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
        XCTAssertTrue(store.espansoFiles.isEmpty, "an imported file leaves the candidate list")
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
            containsShellVars: true
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
            containsShellVars: true
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
        XCTAssertFalse(store.activeTriggers().contains(":t"), "a declined snippet stays inactive")
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
        XCTAssertTrue(store.appSnippets.isEmpty,
                      "an edit that cannot be saved must be refused, not shown as if it worked")
    }

    /// The block has to be escapable. While it was only clearable by relaunching,
    /// the session in between silently swallowed every new snippet: the list
    /// accepted them, nothing reached disk, all gone after the restart.
    func testRepairingTheFileLiftsTheSaveBlock() throws {
        let supportDir = tempDir.appendingPathComponent("Tippi", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let file = supportDir.appendingPathComponent("AppSnippets.json")
        try "{ broken".write(to: file, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.matchDirectory = tempDir
        XCTAssertNotNil(store.appSnippetsLoadError)

        try "[]".write(to: file, atomically: true, encoding: .utf8)
        store.reloadAppSnippets()
        XCTAssertNil(store.appSnippetsLoadError, "a repaired file must clear the block")

        store.addSnippet(shortcut: ":neu", replacement: "x")
        XCTAssertEqual(store.appSnippets.count, 1)
        let onDisk = try Data(contentsOf: file)
        XCTAssertFalse(try XCTUnwrap(String(data: onDisk, encoding: .utf8)).isEmpty)
        XCTAssertNotNil(try? JSONDecoder().decode([AppSnippet].self, from: onDisk),
                        "the snippet must actually reach disk once the block is lifted")
    }

    /// `ImportedSnippets.json` carries the shell approvals, so the same
    /// "unreadable looks empty" collapse costs every consent decision: the list
    /// came up empty and the next import wrote one entry over all of them.
    func testCorruptImportedSnippetFileBlocksSavingInsteadOfOverwritingIt() throws {
        let supportDir = tempDir.appendingPathComponent("Tippi", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let file = supportDir.appendingPathComponent("ImportedSnippets.json")
        try "{ half written".write(to: file, atomically: true, encoding: .utf8)

        let yaml = """
        matches:
          - trigger: ":a"
            replace: "A"
        """
        let source = tempDir.appendingPathComponent("base.yml")
        try yaml.write(to: source, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.matchDirectory = tempDir
        XCTAssertTrue(store.importedSnippets.isEmpty)
        XCTAssertNotNil(store.importedSnippetsLoadError,
                        "a parse failure must be reported, not silently shown as 'nothing imported'")

        XCTAssertEqual(store.espansoFiles.count, 1)
        store.importFile(store.espansoFiles[0])
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(onDisk, "{ half written", "the unreadable file must be left untouched")
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

    /// A trigger duplicated inside one file must collapse to one entry, and
    /// keep the first — the same way the file would have been read top-down.
    /// It used to keep the last, so importing changed what a snippet meant.
    func testDuplicateTriggerInOneFileKeepsTheFirst() throws {
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

        store.importFile(store.espansoFiles[0])
        XCTAssertEqual(store.importedSnippets.count, 1, "the duplicate must not become a second entry")
        XCTAssertEqual(store.importedSnippets[0].replace, "erste")
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

        // Keeping both is only half an answer: exactly one of them expands, and
        // the user has to be able to see which. Asserting the count alone left
        // the meaning untested — the list showed two near-identical rows with
        // no hint that the second was inert.
        let winner = try XCTUnwrap(store.importedSnippets.first)
        let loser = store.importedSnippets[1]
        XCTAssertTrue(store.shadowedTriggers(of: loser).contains(":mw"),
                      "the entry that does not expand must be marked as overridden")
        XCTAssertTrue(store.shadowedTriggers(of: winner).isEmpty,
                      "the entry that does expand must not be marked")

        guard case .espansoMatch(let match)? = store.action(forTrigger: ":mw") else {
            return XCTFail("the trigger must still resolve")
        }
        XCTAssertEqual(match.replace, winner.replace,
                       "the badge must agree with what typing the trigger actually produces")
    }

    /// An unapproved shell snippet sitting earlier in the list must not be
    /// reported as the winner — `action(forTrigger:)` skips it, so marking the
    /// approved entry behind it as "overridden" would be exactly backwards.
    func testUnapprovedSnippetDoesNotShadowAnApprovedOne() throws {
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir

        // Imported through the real path rather than assigned, so the ordering
        // under test is the one production actually produces.
        try """
        matches:
          - trigger: ":x"
            replace: "{{v}}"
            vars:
              - name: v
                type: shell
                params:
                  cmd: echo hi
        """.write(to: tempDir.appendingPathComponent("a-shell.yml"), atomically: true, encoding: .utf8)
        try """
        matches:
          - trigger: ":x"
            replace: "klartext"
        """.write(to: tempDir.appendingPathComponent("b-plain.yml"), atomically: true, encoding: .utf8)
        store.reloadEspansoFiles()

        store.importFile(try XCTUnwrap(store.espansoFiles.first { $0.id.hasSuffix("a-shell.yml") }))
        store.importFile(try XCTUnwrap(store.espansoFiles.first { $0.id.hasSuffix("b-plain.yml") }))

        let shell = try XCTUnwrap(store.importedSnippets.first { $0.hasShellVars })
        let plain = try XCTUnwrap(store.importedSnippets.first { !$0.hasShellVars })
        XCTAssertEqual(store.importedSnippets.first?.id, shell.id, "precondition: the shell entry is first")

        XCTAssertFalse(store.isImportedSnippetActive(shell), "precondition: unapproved shell snippet is inert")
        XCTAssertTrue(store.shadowedTriggers(of: shell).isEmpty,
                      "an inert entry is not shadowed — it simply does not participate")
        XCTAssertTrue(store.shadowedTriggers(of: plain).isEmpty,
                      "nothing ahead of it actually wins, so it must not be marked")
    }
}
