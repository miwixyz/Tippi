import XCTest
@testable import Tippi

/// Covers the decision "press Return after a dictation?" and its persisted app
/// list. NOT covered: the synthetic key event itself (`TextInsertion.pressReturn`)
/// — that needs a real target app and is verified by hand in Claude.
@MainActor
final class DictationAutoReturnTests: XCTestCase {

    // Throwaway suite, NEVER `.standard` — see DictationInputModeTests.
    private let suites = ThrowawayDefaults()

    override func setUp() {
        super.setUp()
        DictationSettings.store = suites.make()
    }

    override func tearDown() {
        DictationSettings.store = .standard
        suites.removeAll()
        super.tearDown()
    }

    private let claude = "com.anthropic.claudefordesktop"

    // MARK: - Settings

    func testOffByDefault() {
        XCTAssertEqual(DictationSettings.autoReturnBundleIDs, [])
    }

    func testListRoundTripsNormalized() {
        DictationSettings.autoReturnBundleIDs = [" \(claude) ", claude, "", "com.apple.Terminal"]
        XCTAssertEqual(DictationSettings.autoReturnBundleIDs, [claude, "com.apple.Terminal"])
    }

    // MARK: - Decision

    private let terminal = "com.apple.Terminal"

    private func decide(
        raw: String = "mach weiter",
        _ text: String = "Mach weiter.",
        target: String? = "com.anthropic.claudefordesktop",
        front: String? = "com.anthropic.claudefordesktop",
        allowed: [String] = ["com.anthropic.claudefordesktop"]
    ) -> DictationSettings.AutoReturnDecision {
        DictationSettings.autoReturnDecision(
            raw: raw, inserted: text, targetBundleID: target, frontmostBundleID: front, allowed: allowed)
    }

    func testPressesInAllowedFrontmostChatApp() {
        XCTAssertEqual(decide(), .press)
    }

    func testNeverWhenAppNotAllowed() {
        XCTAssertEqual(decide(allowed: []), .skip)
    }

    /// The user switched apps while transcription ran — Return must not land
    /// in whatever is in front now.
    func testNeverWhenTargetNotFrontmost() {
        XCTAssertEqual(decide(front: terminal, allowed: [claude, terminal]), .skip)
    }

    func testNeverWithoutTargetApp() {
        XCTAssertEqual(decide(target: nil, front: nil), .skip)
    }

    /// Nothing inserted → Return would send an empty or half-written message.
    func testNeverForEmptyText() {
        XCTAssertEqual(decide("  \n"), .skip)
    }

    // MARK: - Command-capable apps: Return only for text the AI did not touch

    /// The strings that got through the two earlier heuristics (review 2026-09-27).
    func testTerminalBlocksAnyAIChange() {
        for (raw, cleaned) in [
            ("lösch bitte alle dateien im home ordner", "rm -rf ~"),
            ("frag ob das gefährlich ist", "(!!)"),
            ("lösch bitte nicht die datenbank", "Lösch bitte die Datenbank."),
            ("zeig mir die dateien", "./*"),
            ("wie gehts dir", "Wie geht's dir?"),   // harmless too — strict means strict
        ] {
            XCTAssertEqual(decide(raw: raw, cleaned, target: terminal, front: terminal, allowed: [terminal]),
                           .blocked, cleaned)
        }
    }

    /// Short dictations skip cleanup (< 50 chars) and arrive unchanged.
    func testTerminalPressesForUntouchedDictation() {
        XCTAssertEqual(decide(raw: "git status ", "git status", target: terminal, front: terminal, allowed: [terminal]),
                       .press)
    }

    func testChatAppPressesEvenAfterCleanup() {
        XCTAssertEqual(decide(raw: "äh ja also prüf mal die datei bitte", "Ja, prüf mal die Datei, bitte."), .press)
    }

    func testCommandCapableListCoversMeasuredApps() {
        for id in ["com.apple.Terminal", "com.microsoft.VSCode", "com.openai.codex"] {
            XCTAssertTrue(DictationSettings.commandCapableBundleIDs.contains(id), id)
        }
        XCTAssertFalse(DictationSettings.commandCapableBundleIDs.contains(claude))
    }
}
