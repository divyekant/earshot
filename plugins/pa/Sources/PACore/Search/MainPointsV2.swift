import Foundation

/// "main points", version 2 (phase 2 follow-up spec, R2): each sentence gets points from simple features. The PA
/// still only selects sentences of the document. It writes no new words.
public enum MainPointsV2 {
    /// The points of each feature. Tune them on the development documents only.
    public struct Weights: Equatable, Sendable {
        public var amount: Float = 3
        public var date: Float = 3
        public var request: Float = 3
        public var result: Float = 2
        public var opening: Float = 2
        public var titleWord: Float = 1
        public var titleMax: Float = 2
        public var centralWords: Float = 1
        public var centralNumbers: Float = 1
        public var boilerplate: Float = -5
        public init() {}
    }

    public static let weights = Weights()
    /// Two selected sentences with a higher likeness than this say the same thing.
    public static let sameLimit: Float = 0.9

    /// The features of one sentence. Each one is true or false, except `titleWords`.
    public struct Features: Equatable, Sendable {
        public var amount = false
        public var date = false
        public var request = false
        public var result = false
        public var opening = false
        public var titleWords = 0
        public var centralWords = false
        public var centralNumbers = false
        public var boilerplate = false

        public func points(_ w: Weights) -> Float {
            var p: Float = 0
            if amount { p += w.amount }
            if date { p += w.date }
            if request { p += w.request }
            if result { p += w.result }
            if opening { p += w.opening }
            p += min(w.titleMax, Float(titleWords) * w.titleWord)
            if centralWords { p += w.centralWords }
            if centralNumbers { p += w.centralNumbers }
            if boilerplate { p += w.boilerplate }
            return p
        }

        /// A short label for the bench: the letters of the features that are true.
        public var label: String {
            var s = ""
            if amount { s += "A" }
            if date { s += "D" }
            if request { s += "R" }
            if result { s += "S" }
            if opening { s += "F" }
            if titleWords > 0 { s += "T\(titleWords)" }
            if centralWords { s += "W" }
            if centralNumbers { s += "N" }
            if boilerplate { s += "-" }
            return s.isEmpty ? "." : s
        }
    }

    /// One sentence that the rule can select (6 to 60 words), with its place in the document.
    public struct Sentence: Equatable, Sendable {
        public var text: String
        public var index: Int
        /// The first sentence of the document, or the first sentence after a heading or a "Subject" or "Re" line.
        public var opening: Bool
    }

    // MARK: - Word lists

    static let money = ["pound", "pounds", "euro", "euros", "dollar", "dollars", "pence", "p", "eur", "gbp", "usd"]
    static let units = ["percent", "per", "mm", "cm", "m", "km", "metre", "metres", "meter", "meters", "mile", "miles",
                        "litre", "litres", "liter", "liters", "kg", "g", "tonnes", "bar", "kwh", "square"]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                         "october", "november", "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep",
                         "sept", "oct", "nov", "dec"]
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let datePhrases = ["no later than", "deadline", "o'clock", "today", "tomorrow", "next week", "next month",
                              "end of the month", "end of the week"]
    static let requestPhrases = ["please", "must", "need to", "needs to", "have to", "has to", "required", "should",
                                 "no later than", "deadline", "due", "confirm", "sign", "pay", "send", "return",
                                 "agree", "agreed", "decided", "approved"]
    static let resultPhrases = ["total", "sum", "price", "cost", "fee", "valid until", "starts", "ends", "cancelled",
                                "changed", "moved"]
    static let boilerStarts = ["dear ", "hello", "hi ", "kind regards", "best regards", "regards", "yours sincerely",
                               "yours faithfully", "best wishes", "many thanks", "thank you for", "thanks for"]
    static let boilerPhrases = ["if you have any questions", "do not hesitate", "please contact us if",
                                "we look forward to"]

    /// The lowercased words of a text, with the inner "'" and "," kept in numbers.
    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" || ((ch == "," || ch == "." || ch == ":") && !cur.isEmpty && cur.last!.isNumber) {
                cur.append(ch)
            } else {
                if !cur.isEmpty { out.append(cur.trimmingCharacters(in: CharacterSet(charactersIn: ",.:'"))); cur = "" }
                if ch == "£" || ch == "€" || ch == "$" || ch == "%" { out.append(String(ch)) }
            }
        }
        if !cur.isEmpty { out.append(cur.trimmingCharacters(in: CharacterSet(charactersIn: ",.:'"))) }
        return out.filter { !$0.isEmpty }
    }

    static func isNumber(_ w: String) -> Bool { w.first?.isNumber == true }

    /// True if the phrase is in the words as whole words.
    static func has(_ words: [String], _ phrase: String) -> Bool {
        let p = phrase.split(separator: " ").map(String.init)
        guard p.count <= words.count else { return false }
        for i in 0...(words.count - p.count) where Array(words[i..<i + p.count]) == p { return true }
        return false
    }

    // MARK: - Features

    public static func hasAmount(_ s: String) -> Bool {
        let w = tokens(s)
        for (i, x) in w.enumerated() {
            if x == "£" || x == "€" || x == "$" { if i + 1 < w.count, isNumber(w[i + 1]) { return true } }
            guard isNumber(x) else { continue }
            if i + 1 < w.count {
                let n = w[i + 1]
                if n == "%" || money.contains(n) || units.contains(n) { return true }
            }
            if i > 0, w[i - 1] == "£" || w[i - 1] == "€" || w[i - 1] == "$" { return true }
        }
        return false
    }

    public static func hasDate(_ s: String) -> Bool {
        let w = tokens(s)
        for (i, x) in w.enumerated() {
            if months.contains(x), x != "may" || (i > 0 && isNumber(w[i - 1])) || (i + 1 < w.count && isNumber(w[i + 1])) {
                return true
            }
            if weekdays.contains(x) { return true }
            // A written date such as "12.11.2026" or "12/11/2026", or a clock time such as "14:30".
            let parts = x.split(whereSeparator: { $0 == "." || $0 == "/" })
            if parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return true }
            if x.contains(":"), x.split(separator: ":").count == 2, x.split(separator: ":").allSatisfy({ $0.allSatisfy(\.isNumber) }) { return true }
            if isNumber(x), i + 1 < w.count, ["am", "pm"].contains(w[i + 1]) { return true }
            // "within 30 days", "in 14 days", "two weeks before"
            if x == "within", i + 2 < w.count, ["day", "days", "week", "weeks", "month", "months", "working"].contains(w[i + 2]) { return true }
        }
        return datePhrases.contains { has(w, $0) }
    }

    public static func hasRequest(_ s: String) -> Bool {
        let w = tokens(s)
        return requestPhrases.contains { has(w, $0) }
    }

    public static func hasResult(_ s: String) -> Bool {
        let w = tokens(s)
        return resultPhrases.contains { has(w, $0) }
    }

    public static func isBoilerplate(_ s: String) -> Bool {
        let l = s.lowercased()
        if boilerStarts.contains(where: { l.hasPrefix($0) }) { return true }
        return boilerPhrases.contains { l.contains($0) }
    }

    /// A line that is a heading: short, with no end mark of a sentence.
    static func isHeading(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, !t.isEmpty else { return false }
        if ".!?,;".contains(last) { return false }
        return t.split(separator: " ").count <= 12
    }

    /// The candidate sentences of a text, each with its index and the opening flag.
    public static func sentences(_ text: String) -> [Sentence] {
        var out: [Sentence] = []
        var afterHeading = true
        var index = 0
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            let subject = lower.hasPrefix("subject") || lower.hasPrefix("re:") || lower.hasPrefix("re ")
            var first = true
            for s in TextCut.sentences(line) {
                let n = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).count
                if n >= 6 && n <= 60 {
                    out.append(Sentence(text: s, index: index, opening: (afterHeading && first) || out.isEmpty))
                    index += 1
                }
                first = false
            }
            afterHeading = subject || isHeading(line)
        }
        return out
    }

    /// The word graph score of each sentence (the TextRank method): sentences that share words with many others
    /// get a higher score.
    public static func textRank(_ sents: [String]) -> [Float] {
        let terms = sents.map { Set(Words.terms($0).map(Words.stem)) }
        let n = sents.count
        guard n > 1 else { return Array(repeating: 1, count: n) }
        var w = Array(repeating: Array(repeating: Float(0), count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let shared = Float(terms[i].intersection(terms[j]).count)
                guard shared > 0, terms[i].count > 1, terms[j].count > 1 else { continue }
                let v = shared / (log(Float(terms[i].count)) + log(Float(terms[j].count)))
                w[i][j] = v; w[j][i] = v
            }
        }
        let out = w.map { $0.reduce(0, +) }
        var score = Array(repeating: Float(1), count: n)
        for _ in 0..<30 {
            var next = Array(repeating: Float(0.15), count: n)
            for i in 0..<n {
                for j in 0..<n where w[j][i] > 0 && out[j] > 0 { next[i] += 0.85 * w[j][i] / out[j] * score[j] }
            }
            score = next
        }
        return score
    }

    /// The indices of the top fifth (at least 1) of the scores.
    static func topFifth(_ scores: [Float]) -> Set<Int> {
        let k = max(1, Int((Double(scores.count) / 5).rounded(.up)))
        return Set(scores.indices.sorted { scores[$0] > scores[$1] }.prefix(k))
    }

    /// The words of the title: the file name (with "-" and "_" as spaces) and the first line of the text.
    public static func titleTerms(title: String, text: String) -> Set<String> {
        let first = text.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let name = title.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return Set(Words.terms(name + " " + first).map(Words.stem))
    }

    /// The features of each candidate sentence. `vectors` are the numbers of the sentences, in the same order.
    public static func features(_ sents: [Sentence], title: Set<String>, vectors: [[Float]]?) -> [Features] {
        let texts = sents.map(\.text)
        let central = topFifth(textRank(texts))
        var byNumbers = Set<Int>()
        if let vectors, vectors.count == sents.count, !vectors.isEmpty {
            let center = Vectors.mean(vectors)
            let v1 = vectors.enumerated().map { i, v in
                Vectors.dot(v, center) + MainPoints.firstBonus * max(0, 1 - Float(i) / 10)
            }
            byNumbers = topFifth(v1)
        }
        return sents.enumerated().map { i, s in
            var f = Features()
            f.amount = hasAmount(s.text)
            f.date = hasDate(s.text)
            f.request = hasRequest(s.text)
            f.result = hasResult(s.text)
            f.opening = s.opening
            f.titleWords = Set(Words.terms(s.text).map(Words.stem)).intersection(title).count
            f.centralWords = central.contains(i)
            f.centralNumbers = byNumbers.contains(i)
            f.boilerplate = isBoilerplate(s.text)
            return f
        }
    }

    /// Up to `count` sentences of the text, in the order of the document. Each is a part of the text, character
    /// for character. The embedder is optional: with no model, the feature "central by numbers" is off, and no
    /// sentence is dropped as the same as another.
    public static func select(_ text: String, title: String, embedder: Embedder?, count: Int = 5, w: Weights = weights,
                              transform: ([Float]) -> [Float] = Vectors.normalized) throws -> [String] {
        let sents = sentences(text)
        var vecs: [[Float]]?
        if let embedder, !sents.isEmpty {
            var all: [[Float]] = []
            for start in stride(from: 0, to: sents.count, by: 16) {
                all += try embedder.embed(sents[start..<min(sents.count, start + 16)].map(\.text), kind: .passage).map(transform)
            }
            vecs = all
        }
        let feats = features(sents, title: titleTerms(title: title, text: text), vectors: vecs)
        return pick(sents, feats.map { $0.points(w) }, vectors: vecs, count: count)
    }

    /// The selection: the most points first, the earlier sentence on a tie, no sentence that says the same as one
    /// already taken. The result is in the order of the document.
    static func pick(_ sents: [Sentence], _ points: [Float], vectors: [[Float]]?, count: Int) -> [String] {
        let order = sents.indices.sorted { points[$0] != points[$1] ? points[$0] > points[$1] : $0 < $1 }
        var chosen: [Int] = []
        for i in order where chosen.count < count {
            if let v = vectors, chosen.contains(where: { Vectors.dot(v[i], v[$0]) > sameLimit }) { continue }
            chosen.append(i)
        }
        return chosen.sorted().map { sents[$0].text }
    }
}
