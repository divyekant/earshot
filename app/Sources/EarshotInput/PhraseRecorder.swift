import Foundation

/// Records one spoken phrase for the voice enrolment (R-ON-3, D-11). The audio stays in memory. The caller
/// makes the voice profile from it and then drops it. No audio is saved, and no audio leaves the Mac (R-MD-1).
public enum PhraseRecorder {
    /// Records from `source` until the speech ends, or for `maxSeconds`.
    /// - Returns: 16 kHz mono samples.
    public static func record(source: SampleSource = MicrophoneSamples(), maxSeconds: Double = 4,
                              endSilenceMs: Double = 700) async throws -> [Float] {
        let box = RecordBox(maxSamples: Int(maxSeconds * 16000), endSilenceMs: endSilenceMs)
        try source.start { samples in box.add(samples) }
        defer { source.stop() }
        while !box.done { try await Task.sleep(nanoseconds: 50_000_000) }
        return box.samples
    }
}

/// The recording state. The audio thread adds samples, and the task reads them.
final class RecordBox: @unchecked Sendable {
    private let lock = NSLock()
    private let maxSamples: Int
    private var detector: SpeechDetector
    private var all: [Float] = []
    private var pending: [Float] = []
    private var finished = false

    init(maxSamples: Int, endSilenceMs: Double) {
        var config = DetectorConfig()
        config.endSilenceMs = endSilenceMs
        config.minimumSpeechMs = 200
        detector = SpeechDetector(config: config)
        self.maxSamples = maxSamples
    }

    var done: Bool { lock.withLock { finished } }
    var samples: [Float] { lock.withLock { all } }

    func add(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        all.append(contentsOf: samples)
        pending.append(contentsOf: samples)
        let frame = 320  // 20 ms at 16 kHz
        var offset = 0
        while pending.count - offset >= frame {
            let event = detector.feed(db: SpeechDetector.db(pending[offset..<(offset + frame)]))
            offset += frame
            // A drop (a cough or a click) does not end the recording: wait for the phrase.
            if event == .end { finished = true }
        }
        pending.removeFirst(offset)
        if all.count >= maxSamples { finished = true }
    }
}
