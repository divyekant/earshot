import Foundation

/// The bench of the phase 2 follow-up (R1 and R2): `earshot-pa --followup-bench <fixtures folder> --embedder <name>`
/// with `--explain` (the misses of version 1), no flag (the development tables), or `--final` (the one run on the
/// new holdout files). It reads only the made-up fixtures, and the bakeoff folder if one is given.
public final class FollowUpBench {
    let fx: BenchFixtures
    let folder: URL
    let embedder: Embedder
    public var bakeoff: URL?
    public var weights = MainPointsV2.weights
    /// Prints the 8 best sentences of each document, with their features and points.
    public var verbose = false
    /// The needs of the project rule for the final run: neighbors of 5, keywords of 3.
    public var needs = (neighbors: 4, keywords: 3)
    /// The name line in `names()`: off by default, as in the PA (setting proposeByName).
    public var byName = false
    public var out: (String) -> Void = { print($0) }

    public init(folder: URL, embedder: Embedder) throws {
        self.folder = folder
        self.fx = try BenchFixtures.load(folder)
        self.embedder = embedder
    }

    func embed(_ texts: [String], _ kind: EmbedKind) throws -> [[Float]] {
        var all: [[Float]] = []
        for start in stride(from: 0, to: texts.count, by: 16) {
            all += try embedder.embed(Array(texts[start..<min(texts.count, start + 16)]), kind: kind).map(Vectors.normalized)
        }
        return all
    }

    /// The words of a capture with the time phrase cut, as the PA keeps the title.
    static func captureTitle(_ words: String) -> String {
        let reader = TimeReader(calendar: Calendar(identifier: .gregorian))
        let r = reader.read(words, now: Date(timeIntervalSince1970: 1_793_000_000))
        return r.rest.isEmpty ? words : r.rest
    }

    static func keywordText(_ title: String) -> String { ProjectRuleV2.keywordText(title) }

    // MARK: - The records of the owner

    struct Records {
        var project: [String] = []
        var text: [String] = []
        var vec: [[Float]] = []
        var kw: KeywordIndex
        var floor: Float
    }

    func records() throws -> Records {
        var project: [String] = [], text: [String] = []
        for d in fx.docs { for p in TextCut.passages(d.text) { project.append(d.project); text.append(p.text) } }
        for it in fx.items { project.append(it.project); text.append(it.title) }
        let vec = try embed(text, .passage)
        let db = try SQLite(path: ":memory:")
        let kw = try KeywordIndex(db: db, table: "fu_fts")
        for (i, t) in text.enumerated() { try kw.add(Int64(i + 1), t) }
        // The search floor, as in the search bench: the score of the correct result that 95 of 100 development
        // questions reach or pass.
        var keyOf: [String] = []
        for d in fx.docs { for _ in TextCut.passages(d.text) { keyOf.append(d.key) } }
        for it in fx.items { keyOf.append(it.key) }
        var target: [Float] = []
        let qs = fx.questions["dev"] ?? []
        let qv = try embed(qs.map(\.words), .query)
        for (i, q) in qs.enumerated() {
            if let best = keyOf.indices.filter({ keyOf[$0] == q.target }).map({ Vectors.dot(vec[$0], qv[i]) }).max() { target.append(best) }
        }
        let s = target.sorted()
        return Records(project: project, text: text, vec: vec, kw: kw, floor: s.isEmpty ? -1 : s[Int(Double(s.count) * 0.05)])
    }

    func signals(_ caps: [BenchFixtures.Capture], _ r: Records, rule: ProjectRuleV2) throws -> [(signals: ProjectRuleV2.Signals, truth: String, words: String)] {
        let titles = caps.map { Self.captureTitle($0.words) }
        let vecs = try embed(titles, .passage)
        return caps.indices.map { i in
            let scores = r.vec.map { Vectors.dot($0, vecs[i]) }
            let order = r.vec.indices.sorted { scores[$0] > scores[$1] }.prefix(5)
            let hits = r.kw.search(Self.keywordText(titles[i]), limit: 3).map { r.project[Int($0) - 1] }
            let s = rule.signals(words: titles[i], projects: fx.projects, nearest: order.map { (r.project[$0], scores[$0]) },
                                 floor: r.floor, keywordHits: hits)
            return (s, caps[i].project, caps[i].words)
        }
    }

    struct Count { var proposals = 0, correct = 0, covered = 0, withProject = 0; var wrong: Int { proposals - correct } }

    static func count(_ truths: [String], _ proposals: [String?]) -> Count {
        var c = Count()
        for (t, p) in zip(truths, proposals) {
            if t != "none" { c.withProject += 1 }
            guard let p else { continue }
            c.proposals += 1
            if p == t { c.correct += 1; c.covered += 1 }
        }
        return c
    }

    static func line(_ label: String, _ c: Count) -> String {
        let share = c.proposals == 0 ? 0 : Double(c.correct) / Double(c.proposals) * 100
        return String(format: "| %@ | %d | %d (%.0f%%) | %d | %d of %d |", label, c.proposals, c.correct, share, c.wrong, c.covered, c.withProject)
    }

    /// The version 1 profiles and rule, as in the phase 2 bench.
    func versionOne(_ r: Records) throws -> (profiles: [(String, [Float])], rule: ProjectRule) {
        var members: [String: [[Float]]] = [:]
        let names = try embed(fx.projects.map(\.name), .passage)
        for (i, p) in fx.projects.enumerated() { members[p.id, default: []].append(names[i]) }
        for (i, p) in r.project.enumerated() { members[p, default: []].append(r.vec[i]) }
        let profiles = fx.projects.map { ($0.id, Vectors.mean(members[$0.id] ?? [])) }
        let dev = fx.captures["dev"] ?? []
        let dv = try embed(dev.map(\.words), .passage)
        let cases = dev.indices.map { i in (scores: profiles.map { ($0.0, Vectors.dot(dv[i], $0.1)) }, truth: dev[i].project) }
        return (profiles, ProjectRule.fit(cases))
    }

    // MARK: - Explain (3.1 and 4.1)

    public func explain() throws {
        let r = try records()
        let (profiles, rule) = try versionOne(r)
        out(String(format: "## Project version 1 on the old holdout (A %.3f, B %.4f)", rule.a, rule.b))
        out("| Words | Truth | Proposal | Best (score) | Second (score) | Name in words |")
        out("|---|---|---|---|---|---|")
        let caps = fx.captures["holdout"] ?? []
        let vecs = try embed(caps.map(\.words), .passage)
        var wrong = 0, missed = 0
        for (i, c) in caps.enumerated() {
            let s = profiles.map { ($0.0, Vectors.dot(vecs[i], $0.1)) }.sorted { $0.1 > $1.1 }
            let p = rule.propose(s)
            let isWrong = p != nil && p != c.project
            let isMissed = p == nil && c.project != "none"
            guard isWrong || isMissed else { continue }
            if isWrong { wrong += 1 } else { missed += 1 }
            let names = ProjectRuleV2.names(in: c.words, projects: fx.projects).joined(separator: ",")
            out(String(format: "| %@ | %@ | %@ | %@ (%.3f) | %@ (%.3f) | %@ |", c.words, c.project, p ?? "-", s[0].0, s[0].1, s[1].0, s[1].1, names.isEmpty ? "-" : names))
        }
        out("Wrong \(wrong), missed \(missed).")

        out("\n## Main points version 1: the rank of each marked sentence")
        out("| Document | Sentences | Mark | Rank v1 | Selected v1 | Features | Index |")
        out("|---|---|---|---|---|---|---|")
        for p in fx.points {
            let sents = MainPointsV2.sentences(p.text)
            let vecs = try embed(sents.map(\.text), .passage)
            let center = Vectors.mean(vecs)
            let v1 = vecs.enumerated().map { i, v in Vectors.dot(v, center) + MainPoints.firstBonus * max(0, 1 - Float(i) / 10) }
            let rank = sents.indices.sorted { v1[$0] > v1[$1] }
            let sel = try MainPoints.select(p.text, embedder: embedder)
            let feats = MainPointsV2.features(sents, title: MainPointsV2.titleTerms(title: p.name, text: p.text), vectors: vecs)
            for m in p.marks {
                guard let k = sents.firstIndex(where: { $0.text == m }) else {
                    out("| \(p.name) | \(sents.count) | \(m.prefix(50))… | not a sentence | | | |")
                    continue
                }
                out("| \(p.name) | \(sents.count) | \(m.prefix(50))… | \((rank.firstIndex(of: k) ?? -1) + 1) | \(sel.contains(m) ? "yes" : "no") | \(feats[k].label) | \(k + 1) |")
            }
        }
        out("Feature letters: A amount, D date, R request, S result word, F opening, Tn title words, W central by words, N central by numbers, - greeting or closing.")
    }

    // MARK: - Development tables (3.3, 4.3)

    public func development() throws {
        let r = try records()
        out(String(format: "Search floor (from the development questions): %.3f", r.floor))
        let dev = (fx.captures["dev"] ?? []) + (fx.captures["holdout"] ?? [])
        let (profiles, rule1) = try versionOne(r)
        let dv = try embed(dev.map(\.words), .passage)
        let v1 = dev.indices.map { i in rule1.propose(profiles.map { ($0.0, Vectors.dot(dv[i], $0.1)) }) }
        let base = ProjectRuleV2()
        let sig = try signals(dev, r, rule: base)
        var rule = base
        rule.high = ProjectRuleV2.fitHigh(sig.map { ($0.signals, $0.truth) })
        out("\n## Project rule on the development data (old dev and old holdout, \(dev.count) captures)")
        out(rule.high.map { String(format: "H (line 3) from these data: %.3f", $0) } ?? "H: none found, line 3 is off")
        out("| Variant | Proposals | Correct | Wrong | Captures with a project that got a correct proposal |")
        out("|---|---|---|---|---|")
        out(Self.line("Version 1", Self.count(dev.map(\.project), v1)))
        for v in ProjectRuleV2.Variant.allCases {
            out(Self.line(v.rawValue, Self.count(sig.map(\.truth), sig.map { rule.propose($0.signals, variant: v) })))
        }
        // Stricter needs, on the same data (tuning on the development data only).
        for (n, k) in [(4, 2), (5, 2), (4, 3), (5, 3)] {
            var r2 = rule
            r2.neighborsNeed = n; r2.keywordsNeed = k
            out(Self.line("Full rule without line 3, neighbors \(n) of 5, keywords \(k) of 3",
                          Self.count(sig.map(\.truth), sig.map { r2.propose($0.signals, variant: .fullNoH) })))
        }
        for (s, t, w) in sig {
            if let p = rule.propose(s, variant: .fullWithH), p != t { out("wrong: \(w) | truth \(t) | proposal \(p) | \(s)") }
        }
        if let bakeoff { try bakeoffProjects(bakeoff, rule: rule, v1: rule1, floor: r.floor) }

        out("\n## Main points version 2 on the old documents")
        try mainPoints(fx.points, label: "old")
    }

    func mainPoints(_ docs: [(name: String, text: String, marks: [String])], label: String) throws {
        var good = 0, found = 0, notInText = 0
        out("| Document | Marks in the 5 | Missed marks: features (points, rank) |")
        out("|---|---|---|")
        for p in docs {
            let sel = try MainPointsV2.select(p.text, title: p.name, embedder: embedder, w: weights)
            notInText += sel.filter { !p.text.contains($0) }.count
            let n = p.marks.filter { sel.contains($0) }.count
            found += n
            if n >= 2 { good += 1 }
            let sents = MainPointsV2.sentences(p.text)
            let vecs = try embed(sents.map(\.text), .passage)
            let feats = MainPointsV2.features(sents, title: MainPointsV2.titleTerms(title: p.name, text: p.text), vectors: vecs)
            let pts = feats.map { $0.points(weights) }
            let order = sents.indices.sorted { pts[$0] != pts[$1] ? pts[$0] > pts[$1] : $0 < $1 }
            let missed = p.marks.filter { !sel.contains($0) }.compactMap { m -> String? in
                guard let k = sents.firstIndex(where: { $0.text == m }) else { return "not a sentence" }
                return "\(feats[k].label) (\(pts[k]), \((order.firstIndex(of: k) ?? -1) + 1))"
            }
            out("| \(p.name) | \(n) | \(missed.joined(separator: "; ")) |")
            if verbose {
                for k in order.prefix(8) {
                    let mark = p.marks.contains(sents[k].text) ? "*" : " "
                    out("  \(mark) \(pts[k]) \(feats[k].label) [\(k + 1)] \(sents[k].text.prefix(90))")
                }
            }
        }
        out("Main points (\(label)): \(good) of \(docs.count) documents with 2 or more marks; \(found) of \(docs.count * 3) marks; \(notInText) sentences not in the text")
    }

    /// 3.4: dk's research items. The records of a project are its description and the other items with its label.
    func bakeoffProjects(_ folder: URL, rule: ProjectRuleV2, v1: ProjectRule, floor: Float) throws {
        let lines = try String(contentsOf: folder.appendingPathComponent("projects.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { $0.contains(":") }
        let projects = lines.map { (id: String($0.prefix { $0 != ":" }), name: String($0.prefix { $0 != ":" })) }
        var labels: [String: String] = [:]
        for r in try BenchFixtures.rows(folder.appendingPathComponent("labels.tsv")) where r.count >= 2 { labels[r[0]] = r[1] }
        let items = try BenchFixtures.rows(folder.appendingPathComponent("items.tsv")).filter { $0.count >= 2 && labels[$0[0]] != nil }
        let iv = try embed(items.map { Self.captureTitle($0[1]) }, .passage)
        let dv = try embed(lines, .passage)
        let truths = items.map { labels[$0[0]]! }
        let v1p = items.indices.map { i in v1.propose(projects.indices.map { (projects[$0].id, Vectors.dot(iv[i], dv[$0])) }) }
        var v2p: [String?] = [], pap: [String?] = [], v2n: [String?] = [], v2b: [String?] = []
        var detail: [String] = []
        let index = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($1.id, "P\($0 + 1)") })
        for i in items.indices {
            var proj: [String] = [], vec: [[Float]] = [], text: [String] = []
            for (k, p) in projects.enumerated() { proj.append(p.id); vec.append(dv[k]); text.append(lines[k]) }
            for j in items.indices where j != i && truths[j] != "none" { proj.append(truths[j]); vec.append(iv[j]); text.append(items[j][1]) }
            let db = try SQLite(path: ":memory:")
            let kw = try KeywordIndex(db: db, table: "bk_fts")
            for (k, t) in text.enumerated() { try kw.add(Int64(k + 1), t) }
            let scores = vec.map { Vectors.dot($0, iv[i]) }
            let order = vec.indices.sorted { scores[$0] > scores[$1] }.prefix(5)
            let title = Self.captureTitle(items[i][1])
            let hits = kw.search(Self.keywordText(title), limit: 3).map { proj[Int($0) - 1] }
            let s = rule.signals(words: title, projects: projects, nearest: order.map { (proj[$0], scores[$0]) }, floor: -1, keywordHits: hits)
            let p2 = rule.propose(s)
            v2p.append(p2)
            var shipped = rule
            shipped.high = nil
            v2n.append(shipped.propose(s))
            var named = shipped
            named.byName = true
            v2b.append(named.propose(s))
            // The same rule as in the PA: the search floor, and 3 or more records for a project.
            let recs = proj.indices.map { ProjectRuleV2.Record(project: proj[$0], vector: vec[$0], text: text[$0]) }
            let e = shipped.evaluate(title: title, vector: iv[i], records: recs, projects: projects, floor: floor)
            pap.append(e.proposal)
            // One line for each proposal of the bench rule. Only numbers and labels P1..Pn: no item text.
            if let p2 {
                let line = rule.byName && s.name == p2 ? "name" : (s.keywordsCount >= rule.keywordsNeed ? "neighbors and keywords" : "line 3")
                let n = proj.filter { $0 == p2 }.count
                detail.append(String(format: "| %d | %@ | %@ | %@ | %@ | %d | %d of 5 | %d of 3 | %.3f | %@ |", detail.count + 1, line,
                                     index[p2] ?? "?", index[truths[i]] ?? "none", p2 == truths[i] ? "yes" : "no", n,
                                     s.neighborsCount, s.keywordsCount, s.nearest, e.proposal == nil ? "none" : (index[e.proposal!] ?? "?")))
            }
        }
        out("\n## dk's research items (\(items.count) labeled)")
        out("| Variant | Proposals | Correct | Wrong | Captures with a project that got a correct proposal |")
        out("|---|---|---|---|---|")
        out(Self.line("Version 1 (rule of the development set)", Self.count(truths, v1p)))
        out(Self.line((rule.high == nil ? "Version 2 (full rule" : "Version 2 (full rule with line 3") + (rule.byName ? ")" : ", name line off)"), Self.count(truths, v2p)))
        out(Self.line("Version 2 without line 3, name line on (proposeByName true)", Self.count(truths, v2b)))
        out(Self.line("Version 2 without line 3, name line off (the default in the PA)", Self.count(truths, v2n)))
        out(Self.line(String(format: "Version 2 as in the PA (floor %.3f, 3 or more records)", floor), Self.count(truths, pap)))
        out("\nEach proposal of version 2 (full rule). Records: the records of the proposed project (its description and the other labeled items).")
        out("| # | Line | Proposed | Truth | Correct | Records | Neighbors | Keywords | Nearest | As in the PA |")
        out("|---|---|---|---|---|---|---|---|---|---|")
        detail.forEach(out)
    }

    // MARK: - The one final run (3.3, 4.4)

    /// Follow-up ask 3: the name line. `capture-names.tsv` has 10 captures for a named project and 10 with the
    /// name words in another sense. Run one time.
    public func names() throws {
        let r = try records()
        var rule = ProjectRuleV2()
        rule.neighborsNeed = needs.neighbors
        rule.keywordsNeed = needs.keywords
        rule.byName = byName
        let caps = try BenchFixtures.rows(folder.appendingPathComponent("capture-names.tsv")).filter { $0.count >= 2 }
            .map { BenchFixtures.Capture(words: $0[0], project: $0[1]) }
        let sig = try signals(caps, r, rule: rule)
        let proposals = sig.map { rule.propose($0.signals) }
        out("## Name line: capture-names.tsv (neighbors \(needs.neighbors) of 5, keywords \(needs.keywords) of 3, name line \(rule.byName ? "on" : "off"))")
        out("| Captures | Proposals | Correct | Wrong |")
        out("|---|---|---|---|")
        for (label, range) in [("For the named project (1-10)", 0..<10), ("Name words in another sense (11-20)", 10..<20)] {
            let part = range.filter { $0 < sig.count }
            let c = Self.count(part.map { sig[$0].truth }, part.map { proposals[$0] })
            out("| \(label) | \(c.proposals) | \(c.correct) | \(c.wrong) |")
        }
        out("\n| # | Capture | Truth | Proposal | Line | Name | Neighbors | Keywords |")
        out("|---|---|---|---|---|---|---|---|")
        for (i, x) in sig.enumerated() {
            let p = proposals[i]
            let line = p == nil ? "-" : (x.signals.name == p ? "name" : "neighbors and keywords")
            out("| \(i + 1) | \(x.words) | \(x.truth) | \(p ?? "-") | \(line) | \(x.signals.name ?? "-") | \(x.signals.neighbors ?? "-") \(x.signals.neighborsCount) | \(x.signals.keywords ?? "-") \(x.signals.keywordsCount) |")
        }
    }

    public func final(variant: ProjectRuleV2.Variant) throws {
        let r = try records()
        let dev = (fx.captures["dev"] ?? []) + (fx.captures["holdout"] ?? [])
        var rule = ProjectRuleV2()
        rule.neighborsNeed = needs.neighbors
        rule.keywordsNeed = needs.keywords
        rule.high = ProjectRuleV2.fitHigh(try signals(dev, r, rule: rule).map { ($0.signals, $0.truth) })
        let caps = try BenchFixtures.rows(folder.appendingPathComponent("capture-holdout-2.tsv")).filter { $0.count >= 2 }
            .map { BenchFixtures.Capture(words: $0[0], project: $0[1]) }
        let sig = try signals(caps, r, rule: rule)
        let c = Self.count(sig.map(\.truth), sig.map { rule.propose($0.signals, variant: variant) })
        out("## Final run: project rule version 2 (\(variant.rawValue), neighbors \(needs.neighbors) of 5, keywords \(needs.keywords) of 3) on capture-holdout-2.tsv")
        out("| Variant | Proposals | Correct | Wrong | Captures with a project that got a correct proposal |")
        out("|---|---|---|---|---|")
        out(Self.line(variant.rawValue, c))
        let share = c.proposals == 0 ? 0 : Double(c.correct) / Double(c.proposals) * 100
        out("Project pass: \(c.proposals > 0 && share >= 90 && c.wrong <= 5 ? "yes" : "no")")

        let dir = folder.appendingPathComponent("points-holdout")
        var marks: [String: [String]] = [:]
        for row in try BenchFixtures.rows(dir.appendingPathComponent("marks.tsv")) where row.count >= 2 { marks[row[0], default: []].append(row[1]) }
        var docs: [(name: String, text: String, marks: [String])] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where name.hasSuffix(".txt") {
            let key = String(name.dropLast(4))
            docs.append((key, try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8), marks[key] ?? []))
        }
        out("\n## Final run: main points version 2 on points-holdout/")
        try mainPoints(docs, label: "holdout")
    }
}
