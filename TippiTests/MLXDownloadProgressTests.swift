import XCTest
@testable import Tippi

/// Covers the parser that turns `mlx_lm.server` stderr into the download line
/// shown in Settings.
///
/// The interesting property is not "does it read a percentage" but *where the
/// percentages come from*: `huggingface_hub` draws tqdm bars that redraw in
/// place with carriage returns. A parser that splits on newlines alone returns
/// nothing for the entire duration of a multi-GB download — the exact case this
/// feature exists to report — while looking perfectly correct in a test that
/// feeds it newline-terminated input. Several tests below therefore use `\r`
/// deliberately.
@MainActor
final class MLXDownloadProgressTests: XCTestCase {

    func testParsesFileProgressWithSizes() {
        let line = "model-00001-of-00002.safetensors:  45%|████▌     | 1.80G/4.00G [01:23<01:41, 21.7MB/s]"
        let result = MLXServerManager.parseDownloadProgress(line)
        XCTAssertEqual(result, "model-00001-of-00002.safetensors 45% (1.80G/4.00G)")
    }

    func testParsesFileCountProgress() {
        let line = "Fetching 10 files:  30%|███       | 3/10 [00:05<00:12,  1.67s/it]"
        XCTAssertEqual(MLXServerManager.parseDownloadProgress(line), "Fetching 10 files 30% (3/10)")
    }

    /// The regression this whole parser shape exists for: tqdm separates
    /// redraws with `\r`, never `\n`. Splitting on newlines would yield one
    /// giant unparsed blob here.
    func testCarriageReturnSeparatedRedrawsAreParsed() {
        let chunk = "weights.safetensors:   5%|▌ | 0.20G/4.00G [00:03<01:01]\r"
            + "weights.safetensors:  50%|█████ | 2.00G/4.00G [00:30<00:30]\r"
            + "weights.safetensors:  75%|███████▌ | 3.00G/4.00G [00:45<00:15]"
        XCTAssertEqual(
            MLXServerManager.parseDownloadProgress(chunk),
            "weights.safetensors 75% (3.00G/4.00G)",
            "the newest redraw in the chunk must win — earlier ones are already stale"
        )
    }

    /// A bar without a size fragment still has to produce something usable;
    /// falling back to nil here would blank the UI mid-download and let the
    /// idle timeout fire on a download that is in fact progressing.
    func testBarWithoutSizeFragmentStillYieldsPercentage() {
        let line = "Loading weights:  12%|█▏        |"
        XCTAssertEqual(MLXServerManager.parseDownloadProgress(line), "Loading weights 12%")
    }

    func testIgnoresOutputWithoutProgress() {
        XCTAssertNil(MLXServerManager.parseDownloadProgress("INFO: Started server process [12345]"))
        XCTAssertNil(MLXServerManager.parseDownloadProgress(""))
        XCTAssertNil(MLXServerManager.parseDownloadProgress("\r\n"))
    }

    /// Ordinary server chatter mentioning a percent sign must not be mistaken
    /// for a download — a false positive here would hold the startup timeout
    /// open indefinitely on a server that is actually stuck, which is the one
    /// failure that timeout exists to catch. Hence the parser requires the tqdm
    /// bar glyph, not just a number followed by `%`.
    func testPlainTextPercentIsNotTreatedAsProgress() {
        XCTAssertNil(MLXServerManager.parseDownloadProgress("INFO: cache hit rate 95% today"))
        XCTAssertNil(MLXServerManager.parseDownloadProgress("INFO: GPU memory utilisation target"))
    }
}
