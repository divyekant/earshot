import EarshotCore

/// Misheard names (gap item 12, I-15). The owner's answer to a "not sure" note teaches earshot the words that speech
/// wrote for a label: "cloud" for "Claude", "chart" for "Chat". Data, not code: the pairs are in HeardFixes
/// (`heard.json`). No new verb and no app name in code (R-MT-1, DESIGN 3.0).
extension CommandRouter {
    /// The lowest text or sound score between the heard words and the label words. Below it, the answer teaches nothing:
    /// the owner chose a target for another reason.
    static let fixMinScore = 0.5

    /// The heard words in `text` that stand for `label`, and the label words that they stand for, or nil.
    /// It compares each run of 1 to 3 words of the command with each run of label words of about the same length, by
    /// text and by sound, and takes the best pair. Command words, fillers and stop words at the two ends never count,
    /// so the pair holds only the words of the target, not the message text. Nil if the words are already the label.
    public static func heardWords(_ text: String, label: String) -> (heard: String, label: String)? {
        let words = TextKit.words(dropLeadFillers(text))
        let lab = TextKit.words(label)
        guard !words.isEmpty, !lab.isEmpty else { return nil }
        // The owner said the whole label: nothing was misheard.
        let labelKey = lab.joined()
        for n in 1...words.count where n <= lab.count + 2 {
            for s in 0...(words.count - n) where words[s..<(s + n)].joined() == labelKey { return nil }
        }
        let blocked = commandStarts.union(fillers).union(pressOnly).union(sendPhrases)
        let edge = ChatRouter.stopWords.union(blocked)
        var best: (score: Double, heard: [String], label: [String])?
        for n in 1...min(HeardFixes.maxWords, words.count) {
            for s in 0...(words.count - n) {
                let span = Array(words[s..<(s + n)])
                guard !span.contains(where: { blocked.contains($0) }), !edge.contains(span[0]), !edge.contains(span[n - 1])
                else { continue }
                let lo = max(1, n - 1), hi = min(n + 1, lab.count)
                guard lo <= hi else { continue }
                for m in lo...hi {
                    for t in 0...(lab.count - m) {
                        let win = Array(lab[t..<(t + m)])
                        let a = span.joined(), b = win.joined()
                        // A pair that only adds or drops a whole word ("guru" and "guru ai") is not a misheard word.
                        guard a != b, !differsOnlyByWholeWords(span, win) else { continue }
                        let score = max(TextKit.similarity(a, b), SoundCode.similarity(a, b))
                        if score > (best?.score ?? 0) { best = (score: score, heard: span, label: win) }
                    }
                }
            }
        }
        guard let best, best.score >= fixMinScore, best.heard.joined() != best.label.joined() else { return nil }
        return (best.heard.joined(separator: " "), best.label.joined(separator: " "))
    }

    /// True if the two word lists are the same after common words are removed at the two ends, and one list is then empty.
    static func differsOnlyByWholeWords(_ x: [String], _ y: [String]) -> Bool {
        var x = x[...], y = y[...]
        while let a = x.first, a == y.first { x = x.dropFirst(); y = y.dropFirst() }
        while let a = x.last, a == y.last { x = x.dropLast(); y = y.dropLast() }
        return x.isEmpty || y.isEmpty
    }

    /// The decision with misheard words corrected by an earlier answer of the owner, or nil.
    /// Only for a decision that is not sure, or that found nothing. The corrected words go through the same rules
    /// again. The result counts only if it is sure and goes to the same target as the owner's answer (the target key):
    /// the label must be on the screen, in the names or in the app table now. The result is sure at the tier `fuzzy`,
    /// so the press rules stay strict. A risky element and a send have no key, so a correction never makes them sure
    /// (R-NV-5).
    static func fixHeard(_ text: String, _ d: RulesDecision, fixes: HeardFixes, context: RouteContext) -> RulesDecision? {
        guard !d.sure || d.intent == .none, d.intent != .send, !d.awaitsText else { return nil }
        for entry in fixes.matches(TextKit.words(text)) {
            guard let fixed = replacing(text, heard: entry.heard.split(separator: " ").map(String.init), with: entry.label)
            else { continue }
            var n = rules(fixed, context: context)
            guard n.sure, n.intent != .none, n.intent != .send,
                  TieHabits.key(n.intent, screen: context.screen) == entry.key else { continue }
            n.exact = false
            n.why += ", heard \"\(entry.heard)\" as \"\(entry.label)\" (your answer)"
            return n
        }
        return nil
    }

    /// The raw text with the heard words replaced by the label words. The stop mark after the last heard word stays,
    /// so a comma still ends a name. Nil if the words are not in the text as whole pieces.
    static func replacing(_ text: String, heard: [String], with label: String) -> String? {
        let t = Tokens(text)
        let n = heard.count
        guard n > 0, t.count >= n else { return nil }
        for s in 0...(t.count - n) where Array(t.words[s..<(s + n)]) == heard {
            let a = t.piece[s], b = t.piece[s + n - 1]
            // A piece such as "cn/ui" holds two words. Replace only whole pieces.
            guard s == 0 || t.piece[s - 1] != a, s + n == t.count || t.piece[s + n] != b else { continue }
            let tail = String(t.pieces[b].reversed().prefix(while: { ",.;:!?".contains($0) }).reversed())
            let out = Array(t.pieces[..<a]) + [label + tail] + Array(t.pieces[(b + 1)...])
            return out.joined(separator: " ")
        }
        return nil
    }
}
