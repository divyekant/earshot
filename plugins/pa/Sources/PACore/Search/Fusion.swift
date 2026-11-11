import Foundation

/// The merge of result lists by reciprocal rank fusion (phase 2 build spec, 6.6). The score of a result is the sum
/// of 1 / (60 + rank) over the lists. A result in one list only still counts. The rank starts at 1.
public enum Fusion {
    public static let k: Double = 60

    public static func merge<T: Hashable>(_ lists: [[T]]) -> [T] {
        var score: [T: Double] = [:]
        var first: [T: Int] = [:]
        var order = 0
        for list in lists {
            for (i, x) in list.enumerated() {
                score[x, default: 0] += 1 / (k + Double(i + 1))
                if first[x] == nil { first[x] = order; order += 1 }
            }
        }
        return score.keys.sorted { a, b in
            let sa = score[a]!, sb = score[b]!
            return sa != sb ? sa > sb : first[a]! < first[b]!
        }
    }

    /// The list without repeats, in the order of the first time.
    public static func unique<T: Hashable>(_ list: [T]) -> [T] {
        var seen = Set<T>()
        return list.filter { seen.insert($0).inserted }
    }
}
