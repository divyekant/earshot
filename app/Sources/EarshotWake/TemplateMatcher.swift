import Foundation

/// Finds the wake phrase by its sound: the audio templates of the owner's teach takes (D-11, E5).
///
/// A template is the encoder frames of the spoken part of one take (40 ms each, 320 values). For each new encoder
/// frame, a streaming subsequence DTW (dynamic time warping) finds the best match of each template that ends at that
/// frame. The path can stay on a template frame (slower speech) or skip one (faster speech). The score of a match is
/// the mean cosine distance along its path: 0 is the same sound, 1 is an unrelated sound.
///
/// The method uses no spelling, so it works for any phrase, name or language. E5 (10 synthetic voices, 8 phrases):
/// 93 % of the test commands woke it at the limit 0.33, and 8.9 h of own talk gave no false wake.
/// The match does not know the speaker: the voice check stops other people.
///
/// It keeps no audio. One queue calls it. It is not thread-safe.
final class TemplateMatcher {
    /// A match that woke earshot.
    struct Match: Equatable {
        /// The score: the mean of the 2 best templates. 0 is the same sound, 1 is an unrelated sound.
        var score: Double
        /// The worst part: the highest mean cost of 5 frames (200 ms) in a row along the path, for the same
        /// 2 templates. A sound-alike that differs in one syllable has a high worst part. For the log only.
        var worst: Double
        /// The first stream frame of the match of the best template, counted from the last reset.
        var startFrame: Int
        /// The last stream frame of the match.
        var endFrame: Int
    }

    /// The wake limit for the score. E5: 0.30 gave 90 % hits, 0.33 gave 93 %, 0.36 gave 96 %. The lowest score in
    /// 8.9 h of own talk was 0.38, so 0.33 keeps a margin of 0.05.
    static let defaultLimit = 0.33
    /// A local low of the score up to this much above the limit counts as a near miss, for the log.
    static let nearMissMargin = 0.08
    /// The extra cost of a stay or a skip step.
    static let stepCost = 0.05
    /// The most stays on one template frame in a row.
    static let maxStay = 3
    /// The frames of the worst part (200 ms).
    static let worstFrames = 5
    /// The match wakes earshot when no lower score comes in this many next frames (80 ms).
    static let waitFrames = 2
    /// No second wake in this many frames after a wake (1.5 s).
    static let refractoryFrames = 38
    /// The fewest templates for a match. With fewer, earshot uses the spelled spotter.
    static let minTemplates = 3

    let limit: Double
    /// The templates, each frame with length 1.
    let templates: [[[Float]]]

    private var columns: [Column]
    /// The index of the last frame, counted from the last reset.
    private var frameIndex = -1
    /// The results of the last `waitFrames + 1` frames, oldest first.
    private var recent: [Result] = []
    private var lastWake = Int.min / 2
    private var nearMissCount = 0
    private var nearMissBest = Double.infinity
    /// The lowest score of the current run of frames near the limit, and if that run woke earshot.
    private var runLow: Double?
    private var runWoke = false

    /// - Parameter templates: the encoder frames of each take. Templates with fewer than 2 frames are left out.
    init(templates: [[[Float]]], limit: Double = TemplateMatcher.defaultLimit) {
        self.limit = limit
        self.templates = templates.filter { $0.count >= 2 }.map { $0.map(Self.unit) }
        columns = self.templates.map { Column(length: $0.count) }
    }

    /// Feeds one encoder frame. Returns a match when the phrase ended `waitFrames` frames ago.
    func push(_ frame: [Float]) -> Match? {
        frameIndex += 1
        let x = Self.unit(frame)
        var scores: [(score: Double, worst: Double, length: Int)] = []
        scores.reserveCapacity(columns.count)
        for k in 0..<columns.count {
            let costs = templates[k].map { 1 - Double(Self.dot($0, x)) }
            scores.append(columns[k].step(costs: costs))
        }
        let result = Self.combine(scores, frame: frameIndex)
        recent.append(result)
        if recent.count > Self.waitFrames + 1 { recent.removeFirst(recent.count - Self.waitFrames - 1) }

        var match: Match?
        if recent.count == Self.waitFrames + 1, let candidate = recent.first, candidate.score < limit,
           recent.dropFirst().allSatisfy({ candidate.score <= $0.score }),
           candidate.frame - lastWake >= Self.refractoryFrames {
            lastWake = candidate.frame
            runWoke = true
            match = Match(score: candidate.score, worst: candidate.worst, startFrame: candidate.start, endFrame: candidate.frame)
        }
        countNearMiss(result.score)
        return match
    }

    /// The score of the last frame, or infinity if no template fits yet.
    var lastScore: Double { recent.last?.score ?? .infinity }
    /// The worst part of the last frame, or infinity.
    var lastWorst: Double { recent.last?.worst ?? .infinity }

    /// Starts again with no frames. The near-miss count stays until `takeNearMisses`.
    func reset() {
        columns = templates.map { Column(length: $0.count) }
        frameIndex = -1
        recent.removeAll()
        lastWake = Int.min / 2
        runLow = nil
        runWoke = false
    }

    /// The near misses since the last call: the count and the lowest score. Then it starts to count again.
    func takeNearMisses() -> (count: Int, best: Double) {
        let out = (nearMissCount, nearMissBest)
        nearMissCount = 0
        nearMissBest = .infinity
        return out
    }

    /// The lowest score of the templates over a run of frames, for example a whole teach take.
    /// Infinity if no template fits in the frames.
    func lowestScore(_ frames: [[Float]]) -> Double {
        reset()
        var low = Double.infinity
        for frame in frames {
            _ = push(frame)
            low = min(low, lastScore)
        }
        reset()
        _ = takeNearMisses()
        return low
    }

    // MARK: - Parts

    /// The result of one frame: the score, the worst part and the start of the best match.
    private struct Result {
        var score: Double
        var worst: Double
        var start: Int
        var frame: Int
    }

    /// One score for the frame: the mean of the 2 best templates (E5 "best2"). With one template, its score.
    private static func combine(_ scores: [(score: Double, worst: Double, length: Int)], frame: Int) -> Result {
        let order = scores.indices.sorted { scores[$0].score < scores[$1].score }
        guard let best = order.first, scores[best].score.isFinite else {
            return Result(score: .infinity, worst: .infinity, start: frame, frame: frame)
        }
        let used = Array(order.prefix(2))
        let score = used.map { scores[$0].score }.reduce(0, +) / Double(used.count)
        let worst = used.map { scores[$0].worst }.reduce(0, +) / Double(used.count)
        return Result(score: score, worst: worst, start: frame - scores[best].length + 1, frame: frame)
    }

    /// Counts a near miss at the end of each run of frames below `limit + nearMissMargin` that did not wake
    /// earshot and did not go below the limit.
    private func countNearMiss(_ score: Double) {
        if score < limit + Self.nearMissMargin {
            runLow = min(runLow ?? score, score)
            return
        }
        if let low = runLow, !runWoke, low >= limit {
            nearMissCount += 1
            nearMissBest = min(nearMissBest, low)
        }
        runLow = nil
        runWoke = false
    }

    static func unit(_ v: [Float]) -> [Float] {
        var sum: Float = 0
        for value in v { sum += value * value }
        let norm = sum.squareRoot()
        return norm > 1e-10 ? v.map { $0 / norm } : v
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var sum: Float = 0
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for i in 0..<n { sum += pa[i] * pb[i] }
            }
        }
        return sum
    }
}

/// The DTW state of one template: for each template frame, the best path that ends there at the last stream frame.
/// It is the same method as `qbe.py` in `probe/wake-bench` (`_dtw_stream_worst`).
private struct Column {
    /// The sum of the costs along the path, with the step costs.
    var total: [Double]
    /// The stream frames on the path.
    var length: [Int]
    /// The stays on the same template frame in a row.
    var stays: [Int]
    /// The worst part of the path so far.
    var worst: [Double]
    /// The last `worstFrames` costs on the path, oldest first, for each template frame.
    var window: [[Double]]

    init(length n: Int) {
        total = [Double](repeating: .infinity, count: n)
        length = [Int](repeating: 0, count: n)
        stays = [Int](repeating: 0, count: n)
        worst = [Double](repeating: 0, count: n)
        window = [[Double]](repeating: [Double](repeating: 0, count: TemplateMatcher.worstFrames), count: n)
    }

    /// Takes the costs of one stream frame against each template frame.
    /// - Returns: the score of the best path that ends at the last template frame, its worst part and its length
    ///   in stream frames. The score is infinity if no path reaches the end.
    mutating func step(costs: [Double]) -> (score: Double, worst: Double, length: Int) {
        let n = costs.count
        let penalty = TemplateMatcher.stepCost
        let span = TemplateMatcher.worstFrames
        var newTotal = [Double](repeating: .infinity, count: n)
        var newLength = [Int](repeating: 0, count: n)
        var newStays = [Int](repeating: 0, count: n)
        var newWorst = [Double](repeating: 0, count: n)
        var newWindow = window

        // A path can start at the first template frame at any stream frame.
        newTotal[0] = costs[0]
        newLength[0] = 1
        newWindow[0] = [Double](repeating: costs[0], count: span)
        for i in 1..<n {
            let c = costs[i]
            var best = Double.infinity
            var bestLength = 0
            var bestStays = 0
            var source = -1
            // The next template frame.
            if total[i - 1].isFinite {
                let mean = (total[i - 1] + c) / Double(length[i - 1] + 1)
                if mean < best { best = mean; bestLength = length[i - 1] + 1; bestStays = 0; source = i - 1 }
            }
            // The same template frame: the speech is slower than the take.
            if total[i].isFinite, stays[i] < TemplateMatcher.maxStay {
                let mean = (total[i] + c + penalty) / Double(length[i] + 1)
                if mean < best { best = mean; bestLength = length[i] + 1; bestStays = stays[i] + 1; source = i }
            }
            // Skip one template frame: the speech is faster than the take.
            if i >= 2, total[i - 2].isFinite {
                let mean = (total[i - 2] + c + penalty) / Double(length[i - 2] + 1)
                if mean < best { best = mean; bestLength = length[i - 2] + 1; bestStays = 0; source = i - 2 }
            }
            guard source >= 0 else { continue }
            newTotal[i] = best * Double(bestLength)
            newLength[i] = bestLength
            newStays[i] = bestStays
            var costsInWindow = Array(window[source].dropFirst())
            costsInWindow.append(c)
            newWindow[i] = costsInWindow
            let part = costsInWindow.reduce(0, +) / Double(span)
            newWorst[i] = max(worst[source], part)
        }
        total = newTotal
        length = newLength
        stays = newStays
        worst = newWorst
        window = newWindow
        let last = n - 1
        guard newLength[last] > 0 else { return (.infinity, .infinity, 0) }
        return (newTotal[last] / Double(newLength[last]), newWorst[last], newLength[last])
    }
}
