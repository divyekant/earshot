import EarshotCore
import Foundation

/// The last encoder frames of the spotter and the match score of each frame, in memory only (E7). The turn recorder
/// gets the frames around each match. They are not audio: earshot cannot play them back.
struct FrameRing {
    /// The most frames in one trace (5 s).
    static let traceFrames = 125
    /// The frames before the start of the match in a trace (480 ms).
    static let leadFrames = 12

    private(set) var frames: [[Float]] = []
    private(set) var scores: [Double] = []
    /// The index of the last frame, counted from the last reset. -1 before the first frame.
    private(set) var lastIndex = -1

    /// The index of the first kept frame.
    var firstIndex: Int { lastIndex - frames.count + 1 }

    mutating func add(_ frame: [Float], score: Double) {
        frames.append(frame)
        scores.append(score)
        lastIndex += 1
        if frames.count > Self.traceFrames * 2 {
            let drop = frames.count - Self.traceFrames
            frames.removeFirst(drop)
            scores.removeFirst(drop)
        }
    }

    mutating func reset() {
        frames.removeAll(keepingCapacity: true)
        scores.removeAll(keepingCapacity: true)
        lastIndex = -1
    }

    /// The trace from `leadFrames` before the start of the match to the last frame, at most `traceFrames` frames.
    /// The match indexes are counted from the last reset, as the indexes of `TemplateMatcher`.
    func trace(matchStart: Int, matchEnd: Int, limit: Double) -> WakeTrace? {
        guard !frames.isEmpty, matchEnd <= lastIndex else { return nil }
        let first = max(firstIndex, matchStart - Self.leadFrames, lastIndex - Self.traceFrames + 1)
        let from = first - firstIndex
        let kept = Array(frames[from...])
        return WakeTrace(frames: WakeTemplates.pack(kept),
                         scores: scores[from...].map { $0.isFinite ? ($0 * 1000).rounded() / 1000 : nil },
                         firstFrame: first, matchStart: matchStart - first, matchEnd: matchEnd - first, limit: limit)
    }
}
