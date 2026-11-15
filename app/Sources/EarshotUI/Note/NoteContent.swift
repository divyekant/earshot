import Foundation

// The words of the note on screen (R-FB-1), from the text that the command path gives, for example "→ Slack · Ravi"
// or "✗ not sure: … · 1: A · 2: B". Pure, so the tests can check it.

/// What the note shows.
public enum NoteContent: Equatable, Sendable {
    /// A pill: a glyph, the main words, and an aside in a lighter tone.
    case pill(glyph: GlyphKind, text: String, aside: String, failed: Bool)
    /// A question: earshot waits for an answer.
    case question(title: String, question: String, choices: [String], hint: String)
    /// The answer of a plugin, with an optional list.
    case answer(from: String, text: String, items: [AnswerItem])
    /// The listening note.
    case listening

    public struct AnswerItem: Equatable, Sendable {
        public var text: String
        public var when: String
        public var late: Bool
    }

    /// The note of a command result.
    public static func parse(_ raw: String, ok: Bool) -> NoteContent {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("✗") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        text = RecordText.dropArrows(text)

        if text.hasPrefix("not sure") {
            let choices = RecordText.choices(text)
            var why = text.components(separatedBy: " · ").first ?? text
            why = why.replacingOccurrences(of: "not sure: ", with: "").replacingOccurrences(of: "not sure", with: "")
            let question = why.isEmpty ? "Which one?" : RecordText.capital(why)
            let hint = choices.count == 1 ? "Say “yes” or “no”." : "Say “the first one”, “the second one” or “no”."
            return .question(title: "Not sure", question: question, choices: choices, hint: hint)
        }
        if !ok {
            if text.hasPrefix("your voice did not match") {
                return .pill(glyph: .failed, text: "Not your voice", aside: "earshot did nothing", failed: true)
            }
            let parts = text.components(separatedBy: " · ")
            let main = RecordText.capital(RecordText.reason(parts[0]).isEmpty ? parts[0] : RecordText.reason(parts[0]))
            return .pill(glyph: .failed, text: main, aside: parts.dropFirst().first ?? "", failed: true)
        }
        return pill(for: text)
    }

    /// The pill of a done command: the glyph says what kind of thing earshot did.
    static func pill(for text: String) -> NoteContent {
        let parts = text.components(separatedBy: " · ")
        let head = parts[0]
        let aside = parts.dropFirst().joined(separator: " · ")
        if head.hasPrefix("Type"), let n = RecordText.wordCount(head) {
            return .pill(glyph: .typed, text: "Typed \(n) word\(n == 1 ? "" : "s")", aside: "", failed: false)
        }
        if head.hasPrefix("Click menu ") {
            return .pill(glyph: .click, text: "Chose " + head.dropFirst("Click menu ".count), aside: "", failed: false)
        }
        if head.hasPrefix("Click"), let label = RecordText.quoted(head) {
            return .pill(glyph: .click, text: "Clicked “\(label)”", aside: head.hasSuffix("(screen)") ? "Jev picked it" : aside, failed: false)
        }
        if head.hasPrefix("Type") { return .pill(glyph: .typed, text: "Typed", aside: aside, failed: false) }
        if head == "Send" { return .pill(glyph: .sent, text: "Sent", aside: aside, failed: false) }
        if head.hasPrefix("type: waiting") { return .pill(glyph: .text, text: "Say the text", aside: "", failed: false) }
        if aside.hasPrefix("reads this page") { return .pill(glyph: .plugin, text: head, aside: "reads this page", failed: false) }
        if head.hasPrefix("plugin ") { return .pill(glyph: .plugin, text: String(head.dropFirst(7)), aside: aside, failed: false) }
        if head.hasPrefix("Open "), let r = head.range(of: " (plugin ") {
            return .pill(glyph: .open, text: String(head[head.index(head.startIndex, offsetBy: 5)..<r.lowerBound]), aside: "", failed: false)
        }
        if head.hasPrefix("Scroll") || head.hasPrefix("Press") || head == "Back" || head.hasSuffix("numbers") || head.hasPrefix("Undo") {
            return .pill(glyph: head == "Back" ? .back : .check, text: head, aside: aside, failed: false)
        }
        if head == "none" || head == "Nothing to do" { return .pill(glyph: .check, text: "Done", aside: "", failed: false) }
        // An app, or a chat in an app: "Slack · Ravi".
        return .pill(glyph: .open, text: head, aside: aside, failed: false)
    }

    /// The answer of a plugin. A text with list lines ("1. …") becomes a card. A short text is a pill.
    public static func answer(from name: String, text: String) -> NoteContent {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var head: [String] = []
        var items: [AnswerItem] = []
        for line in lines {
            if let r = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                items.append(item(String(line[r.upperBound...])))
            } else if line.hasPrefix("…") {
                items.append(AnswerItem(text: line, when: "", late: false))
            } else {
                head.append(line)
            }
        }
        let first = head.joined(separator: " ")
        if items.isEmpty && first.count <= 64 && lines.count <= 1 {
            return .pill(glyph: .plugin, text: first, aside: name, failed: false)
        }
        return .answer(from: name, text: first, items: items)
    }

    /// "Call the plumber · Wed (late)" gives the text, the time at the right, and the late mark.
    static func item(_ s: String) -> AnswerItem {
        var t = s
        var late = false
        for mark in [" (late)", " · late", "(late)"] where t.hasSuffix(mark) {
            late = true
            t = String(t.dropLast(mark.count))
        }
        if t.lowercased().contains("late,") || t.lowercased().hasPrefix("late ") { late = true }
        if let r = t.range(of: " · ", options: .backwards) {
            return AnswerItem(text: String(t[..<r.lowerBound]), when: String(t[r.upperBound...]), late: late)
        }
        if let r = t.range(of: " — ", options: .backwards) {
            return AnswerItem(text: String(t[..<r.lowerBound]), when: String(t[r.upperBound...]), late: late)
        }
        return AnswerItem(text: t, when: "", late: late)
    }
}
