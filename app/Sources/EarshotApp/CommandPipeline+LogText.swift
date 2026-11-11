import EarshotCore
import Foundation

// Log hygiene (gap item 11): the activity log keeps the command words, not the words that earshot typed.
// A "type …" command, the message of a chat command and hold-key dictation keep only a word count, for example
// "Slack me, (2 words)". The note on screen still shows the text: only the log record changes.

extension CommandPipeline {
    /// The texts that an intent types: the message of a chat, the text of "type …".
    static func typedTexts(_ intent: Intent) -> [String] {
        switch intent {
        case .openChat(_, _, let text?): return [text]
        case .typeInto(_, let text), .typeText(let text): return [text]
        default: return []
        }
    }

    /// The typed texts of a route: its intent and the alternatives that a "not sure" note can show.
    static func typedTexts(_ result: RouteResult) -> [String] {
        ([result.intent] + result.alternatives).flatMap { typedTexts($0) }
    }

    /// "(3 words)" for a text of three words.
    static func wordCount(_ text: String) -> String {
        let n = text.split(whereSeparator: \.isWhitespace).count
        return "(\(n) word\(n == 1 ? "" : "s"))"
    }

    /// The text with each typed text in it replaced by its word count. It matches whole words only and ignores case.
    static func withoutTyped(_ text: String, typed: [String]) -> String {
        var out = text
        let pieces = typed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for piece in Set(pieces).sorted(by: { $0.count > $1.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: piece) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range,
                                                 withTemplate: NSRegularExpression.escapedTemplate(for: wordCount(piece)))
        }
        return out
    }

    /// The heard words for the log: the command words, and a word count for the typed part.
    /// If the router changed the typed words (case, a filler), the text does not contain them. Then the log keeps
    /// the words before the typed part and the count: the typed part is at the end of a "type …" or chat command.
    static func heardForLog(_ heard: String, typed: [String]) -> String {
        let pieces = typed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return heard }
        let replaced = withoutTyped(heard, typed: pieces)
        if replaced != heard { return replaced }
        let longest = pieces.max { $0.count < $1.count } ?? ""
        let n = longest.split(whereSeparator: \.isWhitespace).count
        let words = heard.split(whereSeparator: \.isWhitespace).map(String.init)
        return (words.prefix(max(0, words.count - n)) + [wordCount(longest)]).joined(separator: " ")
    }

    /// The record for the log, with no typed text in its heard words, intent or note.
    static func forLog(_ record: ActivityRecord, typed: [String]) -> ActivityRecord {
        guard !typed.isEmpty else { return record }
        var r = record
        r.heard = heardForLog(record.heard, typed: typed)
        r.intent = withoutTyped(record.intent, typed: typed)
        r.note = withoutTyped(record.note, typed: typed)
        return r
    }
}
