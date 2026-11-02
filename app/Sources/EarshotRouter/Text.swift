import EarshotCore
import Foundation

/// Text helpers for the router. Ported from probe Support.swift (E1, E2).
enum TextKit {
    /// Lower case, letters and digits only, single spaces. The same rule as SafetyPolicy.
    static func normalize(_ s: String) -> String { SafetyPolicy.normalize(s) }

    /// The normalized text with no spaces. "Whats App" and "WhatsApp" have the same key.
    static func key(_ s: String) -> String { normalize(s).replacingOccurrences(of: " ", with: "") }

    /// Hesitation words at the start of a command ("Uh, Slack me running late"). The list is in EarshotCore.
    static var hesitations: Set<String> { Hesitation.words }

    static func words(_ s: String) -> [String] { normalize(s).split(separator: " ").map(String.init) }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = Array(repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }

    /// 1.0 is the same text. 0.0 has nothing in common.
    static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        if longest == 0 { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(longest)
    }

    // MARK: - Numbers (E2, section 7, item 3)

    static func isNumber(_ w: String) -> Bool { !w.isEmpty && w.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 } }

    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
                                      "eighty": 80, "ninety": 90]

    /// Changes number words to digits: "twenty one" gives "21", "three hundred and five" gives "305".
    /// Speech to text gives digits for most numbers. This covers the rest.
    static func digitize(_ words: [String]) -> [String] {
        var out: [String] = []
        var current: Int?
        func flush() { if let c = current { out.append(String(c)); current = nil } }
        for (i, w) in words.enumerated() {
            if let v = units[w] {
                if let c = current, (c % 100 == 0 && c >= 100) || (c % 10 == 0 && c >= 20 && c % 100 != 0 && v < 10) {
                    current = c + v
                } else { flush(); current = v }
            } else if let v = tens[w] {
                if let c = current, c >= 100, c % 100 == 0 { current = c + v } else { flush(); current = v }
            } else if w == "hundred", let c = current, (1...9).contains(c) {
                current = c * 100
            } else if w == "and", let c = current, c >= 100, c % 100 == 0, i + 1 < words.count,
                      units[words[i + 1]] != nil || tens[words[i + 1]] != nil {
                continue
            } else {
                flush()
                out.append(w)
            }
        }
        flush()
        return out
    }
}

/// The words of one utterance, with the place of each word in the raw text.
/// The raw text keeps case and punctuation, so the message text keeps them too.
struct Tokens {
    let pieces: [String]
    private(set) var words: [String] = []
    /// The raw piece of each word.
    private(set) var piece: [Int] = []
    /// Word positions that a comma or another stop mark ends. Position k means: after word k - 1.
    private(set) var stops: [Int] = []

    init(_ text: String) {
        pieces = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for (i, p) in pieces.enumerated() {
            // "Felix's chat" names Felix. Remove the possessive for the match only, not in the raw text.
            let bare = p.replacingOccurrences(of: #"['’]s\b"#, with: "", options: .regularExpression)
            let w = TextKit.words(bare)
            words += w
            piece += Array(repeating: i, count: w.count)
            if !w.isEmpty, let last = p.last, ",;:.!?".contains(last) { stops.append(words.count) }
        }
    }

    var count: Int { words.count }

    /// Removes the first `n` words.
    mutating func dropFirst(_ n: Int) {
        guard n > 0 else { return }
        words.removeFirst(min(n, words.count))
        piece.removeFirst(min(n, piece.count))
        stops = stops.map { $0 - n }.filter { $0 > 0 }
    }

    /// The raw text of the words in `range`, with the stop marks at the two ends removed.
    func raw(_ range: Range<Int>) -> String {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= words.count else { return "" }
        let a = piece[range.lowerBound], b = piece[range.upperBound - 1]
        let joined = pieces[a...b].joined(separator: " ")
        return joined.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:-\u{2014} ").union(.whitespacesAndNewlines))
    }
}
