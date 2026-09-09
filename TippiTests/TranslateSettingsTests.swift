import XCTest
@testable import Tippi

@MainActor
final class TranslateSettingsTests: XCTestCase {
    func testAutoSourceAsksForDetection() {
        let prompt = TranslateSettings.systemPrompt(source: .auto, target: .spanish)
        XCTAssertTrue(prompt.contains("Detect the input language automatically"))
        XCTAssertTrue(prompt.contains("Spanish"))
    }

    func testExplicitSourceNamesBothLanguages() {
        let prompt = TranslateSettings.systemPrompt(source: .german, target: .spanish)
        XCTAssertTrue(prompt.contains("The input is in German"))
        XCTAssertTrue(prompt.contains("Spanish"))
        XCTAssertFalse(prompt.contains("Detect the input language"))
    }

    func testTargetOptionsExcludeAuto() {
        XCTAssertFalse(TranslateLanguage.targetOptions.contains(.auto))
        XCTAssertEqual(TranslateLanguage.targetOptions.count, TranslateLanguage.allCases.count - 1)
    }
}
