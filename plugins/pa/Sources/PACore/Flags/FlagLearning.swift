import Foundation

/// The learning of the request flags (build spec 8.8, with the design thread's note for variant A, 2026-11-12).
/// Variant A is a linear formula: the hand points are the base weights and minus the threshold is the base offset.
/// A flag shows if `w · x + b >= 0`. With the base weights, this is the same as "points >= threshold".
/// The gates do not learn: they stay fixed code.
public struct FlagWeights: Codable, Equatable, Sendable {
    public var w: [Double]
    public var b: Double

    /// The feature names of one example: the sentence features, then "first mail of an organization".
    public static let names = RequestFeatures.sentenceNames + ["first mail of an organization"]

    /// The hand points of variant A and the penalty for a first mail from an organization (FlagBench, RequestModel).
    public static func base(threshold: Double) -> FlagWeights {
        FlagWeights(w: RequestFeatures.handWeights + [-1], b: -threshold)
    }

    public func value(_ x: [Double]) -> Double { zip(w, x).map(*).reduce(0, +) + b }
}

public enum FlagLearning {
    /// The learning starts at this count of answers, with this count or more of each kind.
    public static let minAnswers = 50
    public static let minEach = 10
    /// The guard tests new weights on the last answers.
    public static let guardCount = 20
    /// The one fixed strength of the pull toward the base weights.
    public static let lambda = 0.05

    /// The example of one message: the features of a sentence and the message fact.
    public static func example(_ f: [Double], org: Bool, known: Bool) -> [Double] { f + [org && !known ? 1 : 0] }

    /// The best sentence for the weights, and its value. Nil if the message has no candidate sentence.
    public static func best(_ p: RequestFeatures.Prepared, known: Bool, weights: FlagWeights) -> (index: Int, value: Double, x: [Double])? {
        var out: (Int, Double, [Double])?
        for (i, s) in p.sentences.enumerated() {
            let x = example(s.f, org: p.org, known: known)
            let v = weights.value(x)
            if out == nil || v > out!.1 { out = (i, v, x) }
        }
        return out
    }

    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-max(-30, min(30, z)))) }

    /// A logistic fit of the answers (1 = kept), from the base weights, with a penalty for the distance from them.
    /// The hand points are on a scale of points; `scale` maps points to the logistic scale. 400 steps of plain
    /// gradient descent: well under 1 s for a few hundred answers.
    public static func fit(_ x: [[Double]], _ y: [Double], base: FlagWeights, scale: Double = 1, steps: Int = 400,
                           rate: Double = 0.05) -> FlagWeights {
        var w = base.w, b = base.b
        let n = Double(max(1, x.count))
        for _ in 0..<steps {
            var gw = Array(repeating: 0.0, count: w.count), gb = 0.0
            for (row, t) in zip(x, y) {
                let z = (zip(w, row).map(*).reduce(0, +) + b) * scale
                let e = sigmoid(z) - t
                for j in w.indices { gw[j] += e * row[j] * scale }
                gb += e * scale
            }
            for j in w.indices { w[j] -= rate * (gw[j] / n + lambda * (w[j] - base.w[j])) }
            b -= rate * (gb / n + lambda * (b - base.b))
        }
        return FlagWeights(w: w, b: b)
    }

    /// The count of correct answers: a kept flag that the weights show, or a dropped flag that they do not show.
    static func correct(_ weights: FlagWeights, _ x: [[Double]], _ y: [Double]) -> Int {
        zip(x, y).filter { (weights.value($0.0) >= 0) == ($0.1 > 0.5) }.count
    }

    /// New weights from the answers (oldest first), or nil if the PA keeps the base weights: too few answers, or the
    /// guard fails. The guard fits on all but the last 20 answers, then compares on those 20 with the base weights.
    /// New weights must be better (more correct answers). Then the PA fits on all answers.
    public static func learn(_ answers: [(x: [Double], kept: Bool)], base: FlagWeights) -> FlagWeights? {
        let kept = answers.filter(\.kept).count, dropped = answers.count - kept
        guard answers.count >= minAnswers, kept >= minEach, dropped >= minEach else { return nil }
        let x = answers.map(\.x), y = answers.map { $0.kept ? 1.0 : 0.0 }
        let cut = x.count - guardCount
        let trial = fit(Array(x[..<cut]), Array(y[..<cut]), base: base)
        let testX = Array(x[cut...]), testY = Array(y[cut...])
        guard correct(trial, testX, testY) > correct(base, testX, testY) else { return nil }
        return fit(x, y, base: base)
    }
}
