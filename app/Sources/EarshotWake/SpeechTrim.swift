import Foundation

/// Cuts the quiet audio at the start and the end of a clip.
enum SpeechTrim {
    /// 150 ms of audio more at each end of the loud part.
    static let padSamples = 2400

    /// - Returns: the part from the first to the last loud 20 ms frame, with 150 ms more at each end.
    ///   Empty if no frame is loud.
    static func trim(_ samples: [Float], rate: Int = 16000) -> [Float] {
        guard let speech = span(samples, rate: rate) else { return [] }
        return padded(samples, speech: speech)
    }

    /// The loud part with 150 ms more at each end.
    static func padded(_ samples: [Float], speech: Range<Int>) -> [Float] {
        let start = paddedStart(speech: speech)
        let end = min(samples.count, speech.upperBound + padSamples)
        guard end > start else { return [] }
        return Array(samples[start..<end])
    }

    /// The start of `padded` in the clip.
    static func paddedStart(speech: Range<Int>) -> Int { max(0, speech.lowerBound - padSamples) }

    /// The loud part of a clip: from the first to the last loud 20 ms frame, in samples. Nil if no frame is loud.
    static func span(_ samples: [Float], rate: Int = 16000) -> Range<Int>? {
        let frame = rate / 50
        guard samples.count >= frame else { return nil }
        var levels: [Double] = []
        var i = 0
        while i + frame <= samples.count {
            var sum: Double = 0
            for s in samples[i..<(i + frame)] { sum += Double(s) * Double(s) }
            let rms = (sum / Double(frame)).squareRoot()
            levels.append(rms > 0 ? 20 * log10(rms) : -120)
            i += frame
        }
        let floor = levels.sorted()[levels.count / 10]
        let threshold = max(floor + 12, -50)
        guard let first = levels.firstIndex(where: { $0 >= threshold }),
              let last = levels.lastIndex(where: { $0 >= threshold }) else { return nil }
        return (first * frame)..<min(samples.count, (last + 1) * frame)
    }
}
