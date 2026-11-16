import Foundation

/// The rules arm of experiment E13 (`docs/experiments/E13-footnote-decision-model.md`): the rules of today on an
/// item file of the decision model (`plugins/footnote/model/README.md`). It writes one prediction line for each item.
/// The bench of the model (`uv run fm bench`) reads the predictions and the labels and prints the marks.
///
/// `footnote --decide-bench <items.jsonl> --out <predictions.tsv>`
///
/// It prints counts only, never a text of an item, so that it can run on a sealed set (build spec 2, rule 5).
/// D1 uses the shipped request rule (`RequestWeights`). D4 has no rule today: a flag goes to the morning list
/// (`list`), and no item gives `now`. D2 and D3 are not in this bench: D2 needs the search model, D3 has no rule today.
public final class DecideBench {
    public struct Item {
        public var m: MailMessage
        public var note: Bool
        public var ownerName: String
        public var ownerAddress: String
        /// The owner replied to this sender before, or kept a flag of this sender before (build spec 3.1).
        public var senderKnown: Bool?
        /// The time of the read. The date of the message if the item has no `now`.
        public var now: Date
    }

    public var out: (String) -> Void = { print($0) }

    public init() {}

    /// Reads an item file. A line with no `owner` is an error.
    public static func read(_ url: URL) throws -> [Item] {
        let messages = try FixtureMail.read(url)
        let text = try String(contentsOf: url, encoding: .utf8)
        var items: [Item] = []
        let lines = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for (n, (line, m)) in zip(lines, messages).enumerated() {
            guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let owner = obj["owner"] as? [String: Any], let name = owner["name"] as? String else {
                throw SourceError("line \(n + 1) has no owner")
            }
            // RULE-need.md: a note has an empty `from_address`.
            items.append(Item(m: m, note: (obj["kind"] as? String) == "note" || m.fromAddress.isEmpty, ownerName: name,
                              ownerAddress: (owner["address"] as? String ?? "").lowercased(),
                              senderKnown: obj["sender_known"] as? Bool,
                              now: (obj["now"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? m.date))
        }
        return items
    }

    /// The owner names as the request rule uses them: the words of the name in lower case.
    static func names(_ name: String) -> Set<String> {
        Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    /// The facts line of build spec 3.2, for example
    /// `owner: Maya Rao | kind: mail | sender: person | to: 1 | limit: today | weekday: Tue`.
    /// `limit` is the bucket of the earliest time limit that the time reader finds in a sentence of the text.
    public static func facts(_ it: Item, _ p: RequestFeatures.Prepared, now: Date, reader: TimeReader) -> String {
        let sender = it.note ? "owner" : (p.org ? "org" : "person")
        let cal = reader.calendar
        var earliest: Day?
        for s in p.sentences {
            let r = reader.read(s.text, now: now, todo: true)
            guard r.kind != .none, !r.unsure, let day = r.day ?? r.at.map({ Day($0, cal) }) else { continue }
            if earliest.map({ day < $0 }) ?? true { earliest = day }
        }
        var limit = "none"
        if let e = earliest {
            let d = Day(now, cal).days(to: e, cal)
            limit = d <= 0 ? "today" : d == 1 ? "tomorrow" : d < 7 ? "this week" : "later"
        }
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday = days[(cal.component(.weekday, from: now) + 6) % 7]
        let to = it.note ? 0 : it.m.to.count + it.m.cc.count
        return "owner: \(it.ownerName) | kind: \(it.note ? "note" : "mail") | sender: \(sender) | to: \(to) | limit: \(limit) | weekday: \(weekday)"
    }

    /// The separator of the sentences in the column `sentences` (U+001E, record separator).
    public static let sentenceSeparator = "\u{1E}"

    /// Writes the predictions: `id`, `need` (1 or 0), `need_score`, `when` (none or list), `sentence`, `facts`, and
    /// `sentences`: the sentences of the prepared text (quoted, forwarded and signature parts cut), for the model input.
    public func run(items url: URL, predictions: URL) throws {
        guard let model = RequestModel.fitted else { throw SourceError("no request model") }
        let items = try Self.read(url)
        // A sender is known if an earlier mail of the same owner from this sender passed gate 1 (as in FlagBench),
        // unless the item says it.
        var firstPass: [String: Date] = [:]
        for it in items where !it.note && BulkFilter.reason(it.m, owner: [it.ownerAddress]) == nil {
            let k = it.ownerAddress + " " + it.m.fromAddress.lowercased()
            if firstPass[k].map({ it.m.date < $0 }) ?? true { firstPass[k] = it.m.date }
        }
        let bench = FlagBench(folder: url.deletingLastPathComponent(), embedder: nil)
        var lines = ["id\tneed\tneed_score\twhen\tsentence\tfacts\tsentences"]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let reader = TimeReader(calendar: cal)
        var flags = 0
        for it in items {
            bench.owner = Self.names(it.ownerName)
            bench.ownerAddresses = [it.ownerAddress]
            var l = FlagBench.Labeled(m: it.m, request: false, sentences: [])
            l.note = it.note
            l.known = it.senderKnown ?? (firstPass[it.ownerAddress + " " + it.m.fromAddress.lowercased()].map { $0 < it.m.date } ?? false)
            let p = bench.prepared(l)
            var score = -99.0, sentence = ""
            if bench.gateReason(l) == nil {
                let r = model.score(l.m, p, owner: bench.owner, ownerAddresses: bench.ownerAddresses, known: l.known)
                score = r.score
                sentence = r.best.map { p.sentences[$0].text } ?? ""
            }
            let flag = score >= model.threshold
            if flag { flags += 1 }
            func clean(_ t: String) -> String {
                t.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: Self.sentenceSeparator, with: " ")
            }
            // All sentences of the prepared text, also those that gate 2 does not keep: the model reads them all.
            let all = RequestFeatures.prepare(it.m.text).flatMap { RequestFeatures.sentences($0) }
                .map(clean).joined(separator: Self.sentenceSeparator)
            lines.append("\(it.m.id)\t\(flag ? 1 : 0)\t\(String(format: "%.3f", score))\t\(flag ? "list" : "none")\t\(clean(sentence))\t\(Self.facts(it, p, now: it.now, reader: reader))\t\(all)")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: predictions, atomically: true, encoding: .utf8)
        out("Rules arm (\(model.variant) at \(model.threshold)): \(items.count) items, \(flags) flags")
    }
}
