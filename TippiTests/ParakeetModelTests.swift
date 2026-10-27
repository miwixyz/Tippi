import FluidAudio
import XCTest
@testable import Tippi

/// Parakeet v3 or Ultra (2026-10-27). The default is a decision, not a taste:
/// Ultra is only measured in its makers' benchmarks, not on Michael's German.
/// Until `scripts/parakeet-vergleich.sh` has run on real dictations, nobody
/// should get Ultra without choosing it.
final class ParakeetModelTests: XCTestCase {

    // Throwaway suite, never `.standard` — the test host IS the installed app.
    private let suites = ThrowawayDefaults()

    override func setUp() {
        super.setUp()
        ParakeetModel.store = suites.make()
    }

    override func tearDown() {
        ParakeetModel.store = .standard
        suites.removeAll()
        super.tearDown()
    }

    func testDefaultIsV3() {
        XCTAssertEqual(ParakeetModel.current, .v3, "Ultra stays opt-in until measured on real dictations.")
    }

    func testChoiceIsStored() {
        ParakeetModel.current = .ultra
        XCTAssertEqual(ParakeetModel.current, .ultra)
        ParakeetModel.current = .v3
        XCTAssertEqual(ParakeetModel.current, .v3)
    }

    func testUnknownStoredValueFallsBackToV3() {
        ParakeetModel.store.set("redux", forKey: ParakeetModel.key)
        XCTAssertEqual(ParakeetModel.current, .v3)
    }

    /// The live preview and the final text read the same selection — a
    /// mismatch here would make the preview jump on release.
    func testEachChoiceMapsToItsOwnFluidAudioBuild() {
        XCTAssertEqual(ParakeetModel.v3.asrVersion, .v3)
        XCTAssertEqual(ParakeetModel.ultra.asrVersion, .ultra)
        XCTAssertNotEqual(AsrModels.defaultCacheDirectory(for: ParakeetModel.v3.asrVersion),
                          AsrModels.defaultCacheDirectory(for: ParakeetModel.ultra.asrVersion),
                          "Both builds must live in separate folders so switching never deletes one.")
    }

    func testDisplayNamesNameTheBuild() {
        XCTAssertEqual(ParakeetModel.v3.displayName, "Parakeet v3")
        XCTAssertEqual(ParakeetModel.ultra.displayName, "Parakeet Ultra")
    }
}
