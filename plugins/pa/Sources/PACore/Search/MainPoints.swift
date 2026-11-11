import Foundation

/// "main points" (phase 2 build spec, 8.4). The PA selects sentences of the document. It writes no new words.
public enum MainPoints {
    /// The weight of the score against the likeness to a sentence already selected (maximal marginal relevance).
    public static let lambda: Float = 0.7
    /// The bonus for the first sentences: `firstBonus` for the first sentence, less for each next one, 0 from the 10th.
    public static let firstBonus: Float = 0.05

    /// The sentences that the rule can select: 6 to 60 words.
    public static func candidates(_ text: String) -> [String] {
        TextCut.sentences(text).filter {
            let n = $0.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
            return n >= 6 && n <= 60
        }
    }

    /// Up to `count` sentences of the text, in the order of the document. Each is a part of the text,
    /// character for character.
    public static func select(_ text: String, embedder: Embedder, count: Int = 5,
                              transform: ([Float]) -> [Float] = Vectors.normalized) throws -> [String] {
        let sents = candidates(text)
        guard sents.count > count else { return sents }
        var vecs: [[Float]] = []
        for start in stride(from: 0, to: sents.count, by: 16) {
            let part = Array(sents[start..<min(sents.count, start + 16)])
            vecs += try embedder.embed(part, kind: .passage).map(transform)
        }
        let center = Vectors.mean(vecs)
        let score = vecs.enumerated().map { i, v in
            Vectors.dot(v, center) + firstBonus * max(0, 1 - Float(i) / 10)
        }
        var chosen: [Int] = []
        while chosen.count < count {
            var best = -1
            var bestValue = -Float.greatestFiniteMagnitude
            for i in sents.indices where !chosen.contains(i) {
                let near = chosen.map { Vectors.dot(vecs[i], vecs[$0]) }.max() ?? 0
                let value = lambda * score[i] - (1 - lambda) * near
                if value > bestValue { bestValue = value; best = i }
            }
            guard best >= 0 else { break }
            chosen.append(best)
        }
        return chosen.sorted().map { sents[$0] }
    }
}
