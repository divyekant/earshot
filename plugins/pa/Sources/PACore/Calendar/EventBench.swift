import Foundation

/// The bench of the links by a rule (phase 3 build spec, 9.2):
/// `earshot-pa --events-bench <phase 2 fixtures folder> --events <events tsv> --embedder <name> [--final <lines>]`.
/// With no `--final`, it prints one table for all sets of lines on the file. With `--final L1+L2`, it prints the
/// one line of that set and the go mark. It reads only made-up fixtures.
public final class EventBench {
    public struct Event {
        public var id: String
        public var title: String
        public var people: [String]
        public var day: Day
        public var kind: String
        /// Item keys "kitchen#3" and doc keys "kitchen/quote-tiles".
        public var expected: Set<String>
    }

    public struct Count: Equatable {
        public var alerts = 0
        public var correct = 0
        public var wrong = 0
        /// Events of the kind "want" with an alert.
        public var wantWithAlert = 0
        public var want = 0
    }

    let fx: BenchFixtures
    let embedder: Embedder
    public var out: (String) -> Void = { print($0) }

    public init(corpus folder: URL, embedder: Embedder) throws {
        fx = try BenchFixtures.load(folder)
        self.embedder = embedder
    }

    public static func readEvents(_ url: URL) throws -> [Event] {
        let cal = Calendar(identifier: .gregorian)
        return try BenchFixtures.rows(url).filter { $0.count >= 5 }.map { r in
            let day = Day(text: String(r[3].prefix(10))) ?? Day(Date(), cal)
            var exp = Set<String>()
            for part in (r.count > 5 ? r[5] : "").split(separator: " ") {
                let s = String(part)
                if s.contains("/") {
                    exp.insert(s.hasSuffix(".txt") ? String(s.dropLast(4)) : s)
                } else if let colon = s.firstIndex(of: ":") {
                    let p = s[..<colon]
                    for n in s[s.index(after: colon)...].split(separator: ",") { exp.insert("\(p)#\(n)") }
                }
            }
            return Event(id: r[0], title: r[1], people: r[2].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }, day: day, kind: r[4], expected: exp)
        }
    }

    func embed(_ texts: [String], _ kind: EmbedKind) throws -> [[Float]] {
        var all: [[Float]] = []
        for start in stride(from: 0, to: texts.count, by: 16) {
            all += try embedder.embed(Array(texts[start..<min(texts.count, start + 16)]), kind: kind).map(Vectors.normalized)
        }
        return all
    }

    /// The inputs of the rule for each event: the projects of the 5 nearest owner records, and the project of the
    /// project rule version 2.
    func signals(_ events: [Event]) throws -> [(nearest: [String?], rule: String?)] {
        var records: [ProjectRuleV2.Record] = []
        for d in fx.docs { for p in TextCut.passages(d.text) { records.append(.init(project: d.project, vector: [], text: p.text)) } }
        for it in fx.items { records.append(.init(project: it.project, vector: [], text: it.title)) }
        let vecs = try embed(records.map(\.text), .passage)
        for i in records.indices { records[i].vector = vecs[i] }
        let floor = try searchFloor(records)
        let ev = try embed(events.map(\.title), .passage)
        let rule = ProjectRuleV2()
        return events.indices.map { i in
            let scores = records.map { Vectors.dot($0.vector, ev[i]) }
            let order = records.indices.sorted { scores[$0] > scores[$1] }.prefix(5)
            let p = rule.propose(title: events[i].title, vector: ev[i], records: records, projects: fx.projects, floor: floor)
            return (order.map { Optional(records[$0].project) }, p?.project)
        }
    }

    /// The search floor of the phase 2 bench: the score that 95 of 100 development questions reach.
    func searchFloor(_ records: [ProjectRuleV2.Record]) throws -> Float {
        var keyOf: [String] = []
        for d in fx.docs { for _ in TextCut.passages(d.text) { keyOf.append(d.key) } }
        for it in fx.items { keyOf.append(it.key) }
        let qs = fx.questions["dev"] ?? []
        guard !qs.isEmpty else { return -1 }
        let qv = try embed(qs.map(\.words), .query)
        var target: [Float] = []
        for (i, q) in qs.enumerated() {
            if let best = keyOf.indices.filter({ keyOf[$0] == q.target }).map({ Vectors.dot(records[$0].vector, qv[i]) }).max() {
                target.append(best)
            }
        }
        let s = target.sorted()
        return s.isEmpty ? -1 : s[Int(Double(s.count) * 0.05)]
    }

    func owner() -> ([EventLinker.Project], [EventLinker.Record]) {
        let projects = fx.projects.map { EventLinker.Project(key: $0.id, name: $0.name) }
        var recs: [EventLinker.Record] = []
        for it in fx.items {
            let n = Double(it.key.split(separator: "#").last.flatMap { Int($0) } ?? 0)
            recs.append(.init(key: it.key, project: it.project, title: it.title, order: n))
        }
        for (i, d) in fx.docs.enumerated() {
            recs.append(.init(key: d.key, project: d.project, title: d.key, isDoc: true, order: Double(i)))
        }
        return (projects, recs)
    }

    public func count(_ events: [Event], _ sig: [(nearest: [String?], rule: String?)], lines: EventLinker.Lines,
                      detail: Bool = false) -> Count {
        let (projects, recs) = owner()
        let linker = EventLinker(lines: lines)
        var c = Count()
        for (i, e) in events.enumerated() {
            if e.kind == "want" { c.want += 1 }
            let r = linker.link(title: e.title, people: e.people, day: e.day, projects: projects, records: recs,
                                nearest: sig[i].nearest, ruleProject: sig[i].rule)
            guard !r.isEmpty else {
                if detail { out("  \(e.id) \(e.kind) no alert") }
                continue
            }
            c.alerts += 1
            let ok = e.kind == "want" && !(Set(r.items + r.docs).intersection(e.expected)).isEmpty
            if ok { c.correct += 1 } else { c.wrong += 1 }
            if e.kind == "want" { c.wantWithAlert += 1 }
            if detail { out("  \(e.id) \(e.kind) \(ok ? "correct" : "WRONG") by \(r.lines.label) items \(r.items.count) docs \(r.docs.count)") }
        }
        return c
    }

    static func line(_ label: String, _ c: Count) -> String {
        "| \(label) | \(c.alerts) | \(c.correct) | \(c.wrong) | \(c.wantWithAlert) of \(c.want) |"
    }

    /// The development table, and the selection: the set with the most correct alerts at 1 or fewer wrong alerts.
    public func development(_ file: URL, detail: Bool = false, show: [EventLinker.Lines] = []) throws {
        let events = try Self.readEvents(file)
        let sig = try signals(events)
        out("| Lines | Alerts | Correct | Wrong | Want events with an alert |")
        out("|---|---|---|---|---|")
        var best: (EventLinker.Lines, Count)?
        for set in EventLinker.Lines.allSets {
            let c = count(events, sig, lines: set)
            out(Self.line(set.label, c))
            if c.wrong <= 1, c.correct > (best?.1.correct ?? -1) { best = (set, c) }
        }
        for set in show {
            out("Detail of \(set.label):")
            _ = count(events, sig, lines: set, detail: true)
        }
        if let best {
            out("Selected: \(best.0.label)")
            if detail { _ = count(events, sig, lines: best.0, detail: true) }
        } else {
            out("Selected: none (no set has 1 or fewer wrong alerts)")
        }
    }

    /// The one run on the holdout, with the go mark: 90% or more of the alerts correct, 2 or fewer wrong, and 8 or
    /// more of the 25 events with an alert.
    public func final(_ file: URL, lines: EventLinker.Lines) throws {
        let events = try Self.readEvents(file)
        let sig = try signals(events)
        let c = count(events, sig, lines: lines)
        out("| Lines | Alerts | Correct | Wrong | Want events with an alert |")
        out("|---|---|---|---|---|")
        out(Self.line(lines.label, c))
        let pass = c.alerts > 0 && Double(c.correct) / Double(c.alerts) >= 0.9 && c.wrong <= 2 && c.wantWithAlert >= 8
        out("Go mark: \(pass ? "PASS" : "FAIL")")
    }
}
