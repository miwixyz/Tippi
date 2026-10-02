import AVFoundation

/// Building blocks for `AudioRecorder`'s AVAudioEngine path (2026-10-02).
///
/// Why the recorder moved off `AVAudioRecorder`: that API writes straight to a
/// file and never hands out live buffers, which blocks live transcription in
/// the recording window. Pattern borrowed from Handy (github.com/cjpais/Handy,
/// MIT — idea only, no code): one tap converts every frame to 16 kHz mono and
/// collects it in memory; the WAV is written once, at stop.
/// Spike + measurements: docs/spikes/2026-10-02-live-diktat/.
///
/// Kept free of UI/actor state so the conversion, file and level maths are
/// unit-testable without a microphone.
enum AudioCapture {
    /// Whisper's and Parakeet's input format — and exactly what the old
    /// `AVAudioRecorder` settings produced.
    static let sampleRate: Double = 16_000

    /// 16 kHz mono Float32, non-interleaved — the in-memory format.
    static let processingFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    )!

    /// On-disk format: 16-bit integer PCM WAV, 16 kHz, mono (unchanged from the
    /// `AVAudioRecorder` era, so Whisper/Parakeet see the same files).
    static let fileSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    /// Whether a tap in `client` format can be installed on hardware delivering
    /// `hardware`. During a Bluetooth switch the two disagree for a moment
    /// (24 vs 48 kHz); installing then raises an uncatchable exception.
    static func formatsMatch(hardware: AVAudioFormat, client: AVAudioFormat) -> Bool {
        hardware.sampleRate > 0 && client.sampleRate > 0
            && hardware.sampleRate == client.sampleRate
            && hardware.channelCount == client.channelCount
    }

    /// Level for the waveform UI, mapped like the old `averagePower` meter:
    /// RMS in dBFS, clamped to -60…0, scaled to 0…1.
    static func level(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let dB = max(-60, min(0, 20 * log10(rms)))
        return (dB + 60) / 60
    }

    /// Writes 16 kHz mono samples as a 16-bit WAV. The file is closed (and
    /// complete on disk) when this returns — callers transcribe it right away.
    static func writeWAV(_ samples: [Float], to url: URL) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                            frameCapacity: AVAudioFrameCount(max(1, samples.count))) else {
            throw AudioRecorderError.setupFailed("could not allocate audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        // Scoped so AVAudioFile is released — and the header finalised — before return.
        do {
            let file = try AVAudioFile(forWriting: url, settings: fileSettings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            if buffer.frameLength > 0 { try file.write(from: buffer) }
        }
    }
}

/// Converts whatever the input device delivers (48 kHz stereo, 44.1 kHz,
/// Bluetooth 16/24 kHz …) to 16 kHz mono Float32. One instance per input
/// format; it keeps resampler state across buffers, so feed it the stream in order.
final class AudioResampler {
    let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.setupFailed("no usable microphone input (sample rate 0)")
        }
        guard let c = AVAudioConverter(from: inputFormat, to: AudioCapture.processingFormat) else {
            throw AudioRecorderError.setupFailed("cannot convert \(inputFormat) to 16 kHz mono")
        }
        c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        // Mono downmix: average the channels instead of taking only the first one.
        if inputFormat.channelCount > 1 { c.downmix = true }
        self.inputFormat = inputFormat
        self.converter = c
    }

    /// Converts one input buffer; returns the 16 kHz mono samples it produced
    /// (can be empty while the resampler fills its window).
    func convert(_ input: AVAudioPCMBuffer) throws -> [Float] {
        let ratio = AudioCapture.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: AudioCapture.processingFormat, frameCapacity: capacity) else {
            throw AudioRecorderError.setupFailed("could not allocate conversion buffer")
        }
        var fed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error { throw AudioRecorderError.setupFailed(err?.localizedDescription ?? "conversion failed") }
        guard out.frameLength > 0, let ch = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }
}

/// Thread-safe sample store written from the audio render thread and read from
/// the main actor (level/elapsed timer, stop, live snapshot).
final class SampleStore: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastLevel: Float = 0

    func append(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        let lvl = AudioCapture.level(of: chunk[...])
        lock.lock()
        samples.append(contentsOf: chunk)
        lastLevel = lvl
        lock.unlock()
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
    var level: Float { lock.lock(); defer { lock.unlock() }; return lastLevel }

    /// Copy of everything recorded so far — for live transcription (step B).
    func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return samples }

    /// Hands the take over and clears the store, so the voice data doesn't
    /// linger in memory after the WAV is written.
    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let s = samples
        samples = []
        lastLevel = 0
        return s
    }
}
