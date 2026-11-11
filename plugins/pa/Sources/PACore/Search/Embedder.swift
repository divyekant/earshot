import Foundation

/// The kind of a text for an embedding model. Some models want a different prefix for a query and for a passage.
public enum EmbedKind: String, Sendable {
    case query
    case passage
}

/// A model that turns a text into a list of numbers (phase 2 build spec, 6.1). All other code uses this protocol.
/// The `id` names the model and its version. The store keeps the `id` with each list, so a change of the model
/// starts a new index.
public protocol Embedder: AnyObject {
    var id: String { get }
    var dimension: Int { get }
    func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]]
}

/// Small functions for lists of numbers.
public enum Vectors {
    /// The list with length 1. A list of zeros stays as it is.
    public static func normalized(_ v: [Float]) -> [Float] {
        var sum: Float = 0
        for x in v { sum += x * x }
        guard sum > 0 else { return v }
        let k = 1 / sum.squareRoot()
        return v.map { $0 * k }
    }

    /// The dot product. For two lists with length 1, this is the cosine.
    @inline(__always)
    public static func dot(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var s: Float = 0
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for i in 0..<n { s += pa[i] * pb[i] }
            }
        }
        return s
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        dot(normalized(a), normalized(b))
    }

    /// The mean of the lists, with length 1.
    public static func mean(_ vs: [[Float]]) -> [Float] {
        guard let first = vs.first else { return [] }
        var m = [Float](repeating: 0, count: first.count)
        for v in vs { for i in 0..<min(m.count, v.count) { m[i] += v[i] } }
        return normalized(m)
    }

    /// The first `n` numbers, with length 1. Some models keep most of their quality in a shorter list.
    public static func cut(_ v: [Float], to n: Int) -> [Float] {
        guard n > 0, n < v.count else { return v }
        return normalized(Array(v[0..<n]))
    }
}

/// A model with fixed numbers, for tests and as a base in the bench. Each word stem adds to a few fixed
/// positions of the list (feature hashing). Two texts with the same words get near lists. It knows no
/// synonyms, so it is a keyword model in the form of numbers.
public final class HashEmbedder: Embedder {
    public let id: String
    public let dimension: Int

    public init(dimension: Int = 256) {
        self.dimension = dimension
        self.id = "hash-\(dimension)-v1"
    }

    public func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]] {
        texts.map(vector)
    }

    func vector(_ text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        for w in Words.terms(text) {
            let h = HashEmbedder.fnv(Words.stem(w))
            v[Int(h % UInt64(dimension))] += 1
            v[Int((h >> 20) % UInt64(dimension))] += (h >> 40) & 1 == 0 ? 0.5 : -0.5
        }
        return Vectors.normalized(v)
    }

    /// FNV-1a: the same number for the same word on each run (`hashValue` changes on each run).
    static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        return h
    }
}

/// Words of a text for search: lower case, letters and numbers, with common short words removed.
public enum Words {
    public static let stop: Set<String> = [
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "at", "for", "by", "with", "from", "about", "into",
        "is", "are", "was", "were", "be", "been", "do", "does", "did", "has", "have", "had", "it", "its", "this",
        "that", "these", "those", "there", "here", "what", "where", "which", "who", "whom", "when", "how", "why",
        "my", "our", "your", "his", "her", "their", "me", "we", "you", "he", "she", "they", "them", "us", "i",
        "can", "could", "should", "would", "will", "shall", "may", "must", "say", "said", "says", "any", "some",
        "all", "not", "no", "so", "if", "then", "than", "too", "very", "just", "still", "again", "up", "out",
    ]

    /// The words of the text that are not in the stop list.
    public static func terms(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber { cur.append(ch) } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.filter { !stop.contains($0) }
    }

    /// A rough stem: removes a few common English endings. Only the hash model uses it.
    public static func stem(_ w: String) -> String {
        for suffix in ["ing", "ies", "es", "ed", "s"] where w.count > suffix.count + 2 && w.hasSuffix(suffix) {
            return String(w.dropLast(suffix.count))
        }
        return w
    }
}
