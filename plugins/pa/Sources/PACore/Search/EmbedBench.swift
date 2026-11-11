import Foundation

/// The made-up fixtures of phase 2 (phase 2 build spec, 6.3), read from a folder.
public struct BenchFixtures {
    public struct Doc { public var key: String; public var project: String; public var text: String }
    public struct Item { public var key: String; public var project: String; public var title: String }
    public struct Question { public var words: String; public var target: String; public var other: Bool }
    public struct Capture { public var words: String; public var project: String }
    public struct Pair { public var a: String; public var b: String; public var same: Bool }

    public var projects: [(id: String, name: String)] = []
    public var docs: [Doc] = []
    public var items: [Item] = []
    public var questions: [String: [Question]] = [:]
    public var captures: [String: [Capture]] = [:]
    public var points: [(name: String, text: String, marks: [String])] = []
    public var pairs: [Pair] = []

    public init() {}

    /// The rows of a TSV file, with no comment lines.
    static func rows(_ url: URL) throws -> [[String]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("#") }
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    public static func load(_ folder: URL) throws -> BenchFixtures {
        var fx = BenchFixtures()
        let corpus = folder.appendingPathComponent("corpus")
        for r in try rows(corpus.appendingPathComponent("projects.tsv")) where r.count >= 2 {
            fx.projects.append((r[0], r[1]))
        }
        let fm = FileManager.default
        for (pid, _) in fx.projects {
            let dir = corpus.appendingPathComponent(pid)
            for name in try fm.contentsOfDirectory(atPath: dir.path).sorted() where name.hasSuffix(".txt") {
                let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
                fx.docs.append(Doc(key: "\(pid)/\(name.dropLast(4))", project: pid, text: text))
            }
        }
        for r in try rows(corpus.appendingPathComponent("items.tsv")) where r.count >= 4 {
            fx.items.append(Item(key: "\(r[0])#\(r[1])", project: r[0], title: r[3]))
        }
        for set in ["dev", "holdout"] {
            fx.questions[set] = try rows(folder.appendingPathComponent("questions-\(set).tsv")).filter { $0.count >= 3 }
                .map { Question(words: $0[0], target: $0[1], other: $0[2] == "1") }
            fx.captures[set] = try rows(folder.appendingPathComponent("capture-\(set).tsv")).filter { $0.count >= 2 }
                .map { Capture(words: $0[0], project: $0[1]) }
        }
        let pointsDir = folder.appendingPathComponent("points")
        if fm.fileExists(atPath: pointsDir.path) {
            var marks: [String: [String]] = [:]
            for r in try rows(pointsDir.appendingPathComponent("marks.tsv")) where r.count >= 2 { marks[r[0], default: []].append(r[1]) }
            for name in try fm.contentsOfDirectory(atPath: pointsDir.path).sorted() where name.hasSuffix(".txt") {
                let key = String(name.dropLast(4))
                let text = try String(contentsOf: pointsDir.appendingPathComponent(name), encoding: .utf8)
                fx.points.append((key, text, marks[key] ?? []))
            }
        }
        let dup = folder.appendingPathComponent("duplicates.tsv")
        if fm.fileExists(atPath: dup.path) {
            fx.pairs = try rows(dup).filter { $0.count >= 3 }.map { Pair(a: $0[0], b: $0[1], same: $0[2] == "1") }
        }
        return fx
    }
}

/// The project rule of 8.1: propose the best project only if its score is above A, and the distance to the
/// second project is above B.
public struct ProjectRule: Equatable, Sendable {
    public var a: Float
    public var b: Float
    public init(a: Float, b: Float) { self.a = a; self.b = b }

    /// The proposal for one capture, from its scores against each project profile.
    public func propose(_ scores: [(String, Float)]) -> String? {
        let s = scores.sorted { $0.1 > $1.1 }
        guard let first = s.first else { return nil }
        let second = s.count > 1 ? s[1].1 : -1
        return first.1 > a && first.1 - second > b ? first.0 : nil
    }

    public struct Count: Equatable, Sendable {
        public var proposals = 0
        public var correct = 0
        public var wrong: Int { proposals - correct }
        /// Captures that belong to a project and got the correct proposal.
        public var covered = 0
        public var withProject = 0
    }

    public func count(_ cases: [(scores: [(String, Float)], truth: String)]) -> Count {
        var c = Count()
        for x in cases {
            if x.truth != "none" { c.withProject += 1 }
            guard let p = propose(x.scores) else { continue }
            c.proposals += 1
            if p == x.truth { c.correct += 1; c.covered += 1 }
        }
        return c
    }

    /// The values with the most proposals at `maxWrong` or fewer wrong (8.1, step 3). For the same count, the
    /// higher values (fewer risks on new data).
    public static func fit(_ cases: [(scores: [(String, Float)], truth: String)], maxWrong: Int = 3) -> ProjectRule {
        let tops = cases.compactMap { $0.scores.map(\.1).max() }
        let lo = (tops.min() ?? 0) - 0.01, hi = (tops.max() ?? 1) + 0.01
        var best = ProjectRule(a: hi, b: 1)
        var bestCount = -1
        let steps = 120
        for i in 0...steps {
            let a = lo + (hi - lo) * Float(i) / Float(steps)
            for j in 0...60 {
                let b = Float(j) * 0.0025
                let rule = ProjectRule(a: a, b: b)
                let c = rule.count(cases)
                guard c.wrong <= maxWrong else { continue }
                if c.proposals > bestCount || (c.proposals == bestCount && a + b > best.a + best.b) {
                    best = rule
                    bestCount = c.proposals
                }
            }
        }
        return best
    }
}

/// The bench of the phase 2 build spec, 6.5: `earshot-pa --embed-bench <fixtures folder> --embedder <name>`.
/// It needs no private data. It prints one table.
public final class EmbedBench {
    public struct Result {
        public var rows: [(String, String)] = []
        public var searchHoldout = 0
        public var searchHoldoutKeyword = 0
        public var projectPass = false
        public var mainPointsDocs = 0
    }

    let fx: BenchFixtures
    let embedder: Embedder
    let dims: Int?
    public var progress: (String) -> Void = { _ in }
    /// dk's research items (build spec 6.4): a folder with projects.txt ("Name: description"), items.tsv
    /// (id, text) and labels.tsv (id, project or "none"). They stay out of the repository.
    public var bakeoff: URL?

    public init(fixtures: BenchFixtures, embedder: Embedder, dims: Int? = nil) {
        self.fx = fixtures
        self.embedder = embedder
        self.dims = dims
    }

    func transform(_ v: [Float]) -> [Float] {
        dims.map { Vectors.cut(v, to: $0) } ?? Vectors.normalized(v)
    }

    func embed(_ texts: [String], _ kind: EmbedKind) throws -> [[Float]] {
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        for start in stride(from: 0, to: texts.count, by: 16) {
            out += try embedder.embed(Array(texts[start..<min(texts.count, start + 16)]), kind: kind).map(transform)
        }
        return out
    }

    static func ms(_ t: TimeInterval) -> String { String(format: "%.1f ms", t * 1000) }

    public func run() throws -> Result {
        var res = Result()
        func row(_ k: String, _ v: String) { res.rows.append((k, v)); progress("\(k): \(v)") }
        row("Embedder", "\(embedder.id), \(dims ?? embedder.dimension) numbers")

        // The index: passages of each document (7.3) and the title of each item.
        var entryKey: [String] = []
        var entryText: [String] = []
        for d in fx.docs {
            for p in TextCut.passages(d.text) { entryKey.append(d.key); entryText.append(p.text) }
        }
        let passageCount = entryKey.count
        for it in fx.items { entryKey.append(it.key); entryText.append(it.title) }
        row("Index", "\(fx.docs.count) documents, \(passageCount) passages, \(fx.items.count) items")

        let t0 = Date()
        let entryVec = try embed(entryText, .passage)
        row("Embed the index", Self.ms(Date().timeIntervalSince(t0)) + " for \(entryText.count) texts")

        let db = try SQLite(path: ":memory:")
        let kw = try KeywordIndex(db: db, table: "bench_fts")
        for (i, t) in entryText.enumerated() { try kw.add(Int64(i + 1), t) }

        // Search (6.5): the first 3 of the merged list.
        var queryTimes: [TimeInterval] = []
        for set in ["dev", "holdout"] {
            let qs = fx.questions[set] ?? []
            var hitKw = 0, hitVec = 0, hitFused = 0, other = 0, hitOther = 0, hitOtherKw = 0
            for q in qs {
                let kwList = Fusion.unique(kw.search(q.words, limit: 50).map { entryKey[Int($0) - 1] })
                let tq = Date()
                let qv = try embed([q.words], .query)[0]
                queryTimes.append(Date().timeIntervalSince(tq))
                let order = entryVec.indices.sorted { Vectors.dot(entryVec[$0], qv) > Vectors.dot(entryVec[$1], qv) }
                let vecList = Fusion.unique(order.prefix(80).map { entryKey[$0] })
                let fused = Fusion.merge([kwList, vecList])
                let k = kwList.prefix(3).contains(q.target)
                let v = vecList.prefix(3).contains(q.target)
                let f = fused.prefix(3).contains(q.target)
                if k { hitKw += 1 }
                if v { hitVec += 1 }
                if f { hitFused += 1 }
                if q.other {
                    other += 1
                    if f { hitOther += 1 }
                    if k { hitOtherKw += 1 }
                }
            }
            row("Search \(set), first 3", "merged \(hitFused) of \(qs.count); keywords only \(hitKw); numbers only \(hitVec); other words: merged \(hitOther) of \(other), keywords \(hitOtherKw)")
            if set == "holdout" { res.searchHoldout = hitFused; res.searchHoldoutKeyword = hitKw }
        }

        // Project (6.5, 8.1): the profile of each project, the rule from the development set, the check on the holdout.
        var members: [String: [[Float]]] = [:]
        let names = try embed(fx.projects.map(\.name), .passage)
        for (i, p) in fx.projects.enumerated() { members[p.id, default: []].append(names[i]) }
        for (i, key) in entryKey.enumerated() {
            let pid = String(key.prefix { $0 != "/" && $0 != "#" })
            members[pid, default: []].append(entryVec[i])
        }
        let profiles = fx.projects.map { ($0.id, Vectors.mean(members[$0.id] ?? [])) }
        var rule = ProjectRule(a: 1, b: 1)
        for set in ["dev", "holdout"] {
            let caps = fx.captures[set] ?? []
            let vecs = try embed(caps.map(\.words), .passage)
            let cases = caps.indices.map { i in
                (scores: profiles.map { ($0.0, Vectors.dot(vecs[i], $0.1)) }, truth: caps[i].project)
            }
            if set == "dev" { rule = ProjectRule.fit(cases) }
            let c = rule.count(cases)
            let share = c.proposals == 0 ? 0 : Double(c.correct) / Double(c.proposals) * 100
            row("Project \(set)", String(format: "A %.3f, B %.4f: %d proposals, %d correct (%.0f%%), %d wrong; %d of %d with a project got a correct proposal",
                                         rule.a, rule.b, c.proposals, c.correct, share, c.wrong, c.covered, c.withProject))
            if set == "holdout" { res.projectPass = c.proposals > 0 && share >= 90 && c.wrong <= 5 }
        }
        if let bakeoff { try runBakeoff(bakeoff, rule: rule, row: row) }

        // The duplicate notice (8.2): threshold C on the made-up pairs.
        if !fx.pairs.isEmpty {
            let a = try embed(fx.pairs.map(\.a), .passage), b = try embed(fx.pairs.map(\.b), .passage)
            let sims = fx.pairs.indices.map { Vectors.dot(a[$0], b[$0]) }
            var bestC: Float = 1, bestOK = -1
            for c in Set(sims).sorted() {
                let cut = c - 0.0001
                let ok = fx.pairs.indices.filter { (sims[$0] > cut) == fx.pairs[$0].same }.count
                if ok > bestOK || (ok == bestOK && cut > bestC) { bestOK = ok; bestC = cut }
            }
            let same = fx.pairs.indices.filter { fx.pairs[$0].same && sims[$0] > bestC }.count
            let falseSame = fx.pairs.indices.filter { !fx.pairs[$0].same && sims[$0] > bestC }.count
            row("Duplicates", String(format: "C %.3f: %d of 20 same pairs found, %d of 20 different pairs called the same", bestC, same, falseSame))
        }

        // Main points (8.4): 2 or more of the 3 marked sentences in the 5 selected.
        if !fx.points.isEmpty {
            var good = 0, found = 0, notInText = 0
            for p in fx.points {
                let sel = try MainPoints.select(p.text, embedder: embedder, transform: transform)
                notInText += sel.filter { !p.text.contains($0) }.count
                let n = p.marks.filter { sel.contains($0) }.count
                found += n
                if n >= 2 { good += 1 }
            }
            res.mainPointsDocs = good
            row("Main points", "\(good) of \(fx.points.count) documents with 2 or more marks; \(found) of \(fx.points.count * 3) marks; \(notInText) sentences not in the text")
        }

        // Speed (6.5): one passage and one query, with the model loaded.
        let sample = Array(entryText.prefix(10))
        var tp: [TimeInterval] = []
        for s in sample {
            let t = Date()
            _ = try embedder.embed([s], kind: .passage)
            tp.append(Date().timeIntervalSince(t))
        }
        row("Speed", "one passage: median \(Self.ms(Self.median(tp))); one query: median \(Self.ms(Self.median(queryTimes))), slowest 1 in 10 \(Self.ms(Self.p90(queryTimes)))")

        // The compare of all numbers (7.6) for 50,000 passages, with made-up numbers.
        let dim = dims ?? embedder.dimension
        var rng = SplitMix(seed: 7)
        let n = 50_000
        var flat = [Float](repeating: 0, count: n * dim)
        for i in flat.indices { flat[i] = Float(rng.next() % 2000) / 1000 - 1 }
        let q = Vectors.normalized((0..<dim).map { _ in Float(rng.next() % 2000) / 1000 - 1 })
        var times: [TimeInterval] = []
        var checksum: Float = 0
        for _ in 0..<5 {
            let t = Date()
            var best: Float = -2
            flat.withUnsafeBufferPointer { f in
                q.withUnsafeBufferPointer { qp in
                    for r in 0..<n {
                        var s: Float = 0
                        let base = r * dim
                        for k in 0..<dim { s += f[base + k] * qp[k] }
                        if s > best { best = s }
                    }
                }
            }
            times.append(Date().timeIntervalSince(t))
            checksum += best
        }
        // The sum is printed, so that the optimizer keeps the loop.
        row("Compare 50,000 passages", "median \(Self.ms(Self.median(times))) (numbers in memory; best \(String(format: "%.3f", checksum / 5)))")
        return res
    }

    /// The project test of 6.5 on dk's research items: the profile of a project is its name and description.
    func runBakeoff(_ folder: URL, rule: ProjectRule, row: (String, String) -> Void) throws {
        let projects = try String(contentsOf: folder.appendingPathComponent("projects.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { $0.contains(":") }
        let names = projects.map { String($0.prefix { $0 != ":" }) }
        var labels: [String: String] = [:]
        for r in try BenchFixtures.rows(folder.appendingPathComponent("labels.tsv")) where r.count >= 2 { labels[r[0]] = r[1] }
        let items = try BenchFixtures.rows(folder.appendingPathComponent("items.tsv")).filter { $0.count >= 2 && labels[$0[0]] != nil }
        let pv = try embed(projects, .passage)
        let iv = try embed(items.map { $0[1] }, .passage)
        let cases = items.indices.map { i in
            (scores: names.indices.map { (names[$0], Vectors.dot(iv[i], pv[$0])) }, truth: labels[items[i][0]]!)
        }
        let c = rule.count(cases)
        let share = c.proposals == 0 ? 0 : Double(c.correct) / Double(c.proposals) * 100
        row("Project, dk's items (rule of the development set)", String(format: "%d proposals, %d correct (%.0f%%), %d wrong; %d of %d with a project got a correct proposal",
                                                                     c.proposals, c.correct, share, c.wrong, c.covered, c.withProject))
        let refit = ProjectRule.fit(cases)
        let r = refit.count(cases)
        row("Project, dk's items (rule fit on these items, for reference only)", String(format: "A %.3f, B %.4f: %d proposals, %d wrong", refit.a, refit.b, r.proposals, r.wrong))
        let withProject = cases.filter { $0.truth != "none" }
        let top1 = withProject.filter { $0.scores.max { $0.1 < $1.1 }?.0 == $0.truth }.count
        row("Project, dk's items, best project with no threshold", "\(top1) of \(withProject.count) items with a project")
    }

    static func median(_ v: [TimeInterval]) -> TimeInterval {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[s.count / 2]
    }

    static func p90(_ v: [TimeInterval]) -> TimeInterval {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[min(s.count - 1, Int(Double(s.count) * 0.9))]
    }

    /// The table as text.
    public static func table(_ r: Result) -> String {
        var out = "| Measure | Value |\n|---|---|\n"
        for (k, v) in r.rows { out += "| \(k) | \(v) |\n" }
        return out
    }
}

/// A small random number source with a fixed seed, so that each run uses the same numbers.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
