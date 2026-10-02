import AVFoundation
import XCTest
@testable import Tippi

/// AudioRecorder's AVAudioEngine path (2026-10-02): conversion, level and WAV
/// writing are tested here without a microphone. The live take itself is
/// checked by hand (dictation, popup mic, translate) — see the release notes.
final class AudioCaptureTests: XCTestCase {

    private func sine(rate: Double, channels: AVAudioChannelCount, seconds: Double,
                      amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                channels: channels, interleaved: false)!
        let n = AVAudioFrameCount(rate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
        buf.frameLength = n
        for c in 0..<Int(channels) {
            for i in 0..<Int(n) {
                buf.floatChannelData![c][i] = amplitude * sin(2 * .pi * 440 * Float(i) / Float(rate))
            }
        }
        return buf
    }

    /// Feeds `buf` in tap-sized slices (4096 frames), like the engine does.
    private func convertInSlices(_ buf: AVAudioPCMBuffer) throws -> [Float] {
        let r = try AudioResampler(inputFormat: buf.format)
        var out: [Float] = []
        var pos: AVAudioFrameCount = 0
        while pos < buf.frameLength {
            let len = min(4096, buf.frameLength - pos)
            let slice = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: len)!
            slice.frameLength = len
            for c in 0..<Int(buf.format.channelCount) {
                slice.floatChannelData![c].update(from: buf.floatChannelData![c] + Int(pos), count: Int(len))
            }
            out += try r.convert(slice)
            pos += len
        }
        return out
    }

    func testResamples48kStereoToOneSecondOf16kMono() throws {
        let out = try convertInSlices(sine(rate: 48_000, channels: 2, seconds: 1))
        XCTAssertEqual(Double(out.count), 16_000, accuracy: 300, "1 s in → ~16 000 samples out")
        // Downmix keeps the signal: RMS of a 0.5 sine ≈ 0.354, well above silence.
        let mid = out[4_000..<12_000]
        let rms = (mid.reduce(0) { $0 + $1 * $1 } / Float(mid.count)).squareRoot()
        XCTAssertEqual(rms, 0.354, accuracy: 0.05)
    }

    func testResamples44_1kMono() throws {
        let out = try convertInSlices(sine(rate: 44_100, channels: 1, seconds: 2))
        XCTAssertEqual(Double(out.count), 32_000, accuracy: 300)
    }

    func testRejectsInputWithoutSampleRate() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 0, channels: 1)
        if let fmt { XCTAssertThrowsError(try AudioResampler(inputFormat: fmt)) }
    }

    func testLevelMatchesOldMeterScale() {
        XCTAssertEqual(AudioCapture.level(of: [Float](repeating: 0, count: 1600)[...]), 0)
        // Full-scale sine: RMS 0.707 = -3 dBFS → (60-3)/60 = 0.95
        let loud = (0..<1600).map { Float(sin(2 * .pi * 440 * Double($0) / 16_000)) }
        XCTAssertEqual(AudioCapture.level(of: loud[...]), 0.95, accuracy: 0.01)
        // -70 dBFS clamps to the bottom of the -60…0 range
        XCTAssertEqual(AudioCapture.level(of: [Float](repeating: 0.0003, count: 1600)[...]), 0)
    }

    func testWritesSixteenBitMonoWAVWithEverySample() throws {
        let samples = (0..<12_345).map { Float(sin(Double($0) / 10)) * 0.4 }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tippi-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioCapture.writeWAV(samples, to: url)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertEqual(file.fileFormat.settings[AVLinearPCMIsFloatKey] as? Bool, false)
        XCTAssertEqual(file.length, 12_345, "no sample lost or added")

        let back = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: back)
        XCTAssertEqual(back.floatChannelData![0][1_000], samples[1_000], accuracy: 0.001, "16-bit round trip")
    }

    func testEmptyTakeStillWritesAValidFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tippi-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioCapture.writeWAV([], to: url)
        XCTAssertEqual(try AVAudioFile(forReading: url).length, 0)
    }

    /// AirPods mid-take (log 2026-10-02): hardware already 24 kHz, client still
    /// 48 kHz. Installing the tap then would raise an uncatchable exception.
    func testFormatCheckRejectsTheBluetoothSwitchMoment() {
        let hw24 = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let cl48 = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let hw48 = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let st48 = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        XCTAssertFalse(AudioCapture.formatsMatch(hardware: hw24, client: cl48))
        XCTAssertFalse(AudioCapture.formatsMatch(hardware: st48, client: cl48), "channel count differs")
        XCTAssertTrue(AudioCapture.formatsMatch(hardware: hw48, client: cl48))
        XCTAssertTrue(AudioCapture.formatsMatch(hardware: hw24, client: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!))
    }

    func testDrainHandsOverAndClears() {
        let store = SampleStore()
        store.append([0.1, 0.2, 0.3])
        XCTAssertEqual(store.snapshot(), [0.1, 0.2, 0.3])
        XCTAssertEqual(store.count, 3, "snapshot is a copy, the take keeps it")
        XCTAssertEqual(store.drain(), [0.1, 0.2, 0.3])
        XCTAssertEqual(store.count, 0, "no voice data left in memory after stop")
        XCTAssertEqual(store.level, 0)
    }
}
