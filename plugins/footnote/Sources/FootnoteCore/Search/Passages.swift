import Foundation

/// One part of the text of a document (phase 2 build spec, 7.3).
public struct Passage: Equatable, Sendable {
    public var position: Int
    public var page: Int?
    public var text: String
}

/// Cuts text into sentences and passages.
public enum TextCut {
    /// The sentences of the text, in order. Each sentence is a part of the text, character for character,
    /// with no space at the start or the end. A sentence ends at ".", "!" or "?" before a space and a capital
    /// letter, a digit or a quote, and at each line end. "7.4" and "e.g. this" do not end a sentence.
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        let chars = Array(text)
        var start = 0
        func flush(_ end: Int) {
            guard end > start else { return }
            let s = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\n" {
                flush(i)
                start = i + 1
            } else if c == "." || c == "!" || c == "?" {
                var j = i + 1
                while j < chars.count, chars[j] == "\"" || chars[j] == ")" || chars[j] == "'" { j += 1 }
                if j >= chars.count {
                    flush(j)
                    start = j
                    i = j
                    continue
                }
                if chars[j] == " " || chars[j] == "\t" {
                    var k = j
                    while k < chars.count, chars[k] == " " || chars[k] == "\t" { k += 1 }
                    if k < chars.count, chars[k].isUppercase || chars[k].isNumber || chars[k] == "\"" || chars[k] == "\n" {
                        flush(j)
                        start = j
                    }
                }
            }
            i += 1
        }
        flush(chars.count)
        return out
    }

    /// Passages of about `words` words, cut at sentence ends, with one sentence of overlap.
    /// A sentence longer than the limit is a passage alone.
    public static func passages(_ text: String, page: Int? = nil, words: Int = 120, startPosition: Int = 0) -> [Passage] {
        let sents = sentences(text)
        guard !sents.isEmpty else { return [] }
        let counts = sents.map { $0.split(whereSeparator: { $0 == " " || $0 == "\n" }).count }
        var out: [Passage] = []
        var i = 0
        while i < sents.count {
            var j = i
            var n = 0
            while j < sents.count, n == 0 || n + counts[j] <= words {
                n += counts[j]
                j += 1
            }
            out.append(Passage(position: startPosition + out.count, page: page, text: sents[i..<j].joined(separator: " ")))
            if j >= sents.count { break }
            // One sentence of overlap, but always one step forward.
            i = max(i + 1, j - 1)
        }
        return out
    }
}
