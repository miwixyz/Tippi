import XCTest
@testable import Tippi

/// Exercises the per-file consent gate end-to-end against real files in a
/// temp directory — the part of `SnippetStore` most likely to regress
/// silently (see `SnippetStore.fileContentHash`'s comment on why
/// `String.hashValue` would have been a cross-launch-breaking bug).
@MainActor
final class SnippetStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Every store in this file is fully isolated from Michael's real
    /// Tippi installation: a fresh temp directory for file persistence
    /// (AppSnippets.json) and a throwaway UserDefaults suite (never
    /// `.standard`) for settings/approval-hash storage.
    private func makeStore() -> SnippetStore {
        let suiteName = "TippiTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SnippetStore(appSupportRoot: tempDir, userDefaults: defaults)
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
}
