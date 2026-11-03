import Foundation

/// Cuts the quiet audio at the start and the end of a clip.
enum SpeechTrim {
    /// 150 ms of audio more at each end of the loud part.
    static let padSamples = 2400
    /// The longest quiet part that `condensed` keeps inside a clip: 15 frames of 20 ms (300 ms).
    static let maxGapFrames = 15

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
        let loud = loudFrames(samples, rate: rate)
        guard let first = loud.firstIndex(of: true), let last = loud.lastIndex(of: true) else { return nil }
        return (first * frame)..<min(samples.count, (last + 1) * frame)
    }

    /// The trimmed clip with each quiet part inside cut to 300 ms at most. A whole turn has pauses, for example
    /// between the phrase and the command. The voice model then scores the speech, as in the E6 bench, which used
    /// speech with no long pauses.
    /// - Returns: empty if no frame is loud.
    static func condensed(_ samples: [Float], rate: Int = 16000) -> [Float] {
        let frame = rate / 50
        let loud = loudFrames(samples, rate: rate)
        guard let first = loud.firstIndex(of: true), let last = loud.lastIndex(of: true) else { return [] }
        func frames(_ range: Range<Int>) -> ArraySlice<Float> { samples[(range.lowerBound * frame)..<(range.upperBound * frame)] }
        var out = Array(samples[max(0, first * frame - padSamples)..<(first * frame)])
        out.reserveCapacity(samples.count)
        var i = first
        while i <= last {
            if loud[i] { out.append(contentsOf: frames(i..<(i + 1))); i += 1; continue }
            // A quiet part: from i to the next loud frame. The last frame is loud, so it ends before `last`.
            var j = i
            while !loud[j] { j += 1 }
            if j - i <= maxGapFrames {
                out.append(contentsOf: frames(i..<j))
            } else {
                let head = maxGapFrames / 2
                out.append(contentsOf: frames(i..<(i + head)))
                out.append(contentsOf: frames((j - (maxGapFrames - head))..<j))
            }
            i = j
        }
        let end = (last + 1) * frame
        out.append(contentsOf: samples[end..<min(samples.count, end + padSamples)])
        return out
    }

    /// The level of a clip, in dB of full scale (RMS). -120 for silence or an empty clip.
    static func level(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? max(-120, 20 * log10(rms)) : -120
    }

    /// For each whole 20 ms frame: true if it is loud. A frame is loud if it is 12 dB or more over the quietest
    /// tenth of the frames, and at -50 dB or more. Empty if the clip is shorter than one frame.
    static func loudFrames(_ samples: [Float], rate: Int = 16000) -> [Bool] {
        let frame = rate / 50
        guard samples.count >= frame else { return [] }
        var levels: [Double] = []
        levels.reserveCapacity(samples.count / frame)
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
        return levels.map { $0 >= threshold }
    }
}
