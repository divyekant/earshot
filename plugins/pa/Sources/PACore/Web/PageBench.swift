import Foundation

/// The passages of a web page (spec 9.1): about 120 words, cut at sentence ends, one sentence of overlap, and never
/// across two sections. A section starts at each heading. With `headingFront`, each passage starts with the text of
/// the nearest heading in front of it (spec 9.1: use it only if it makes the search better on `pages-dev`).
public enum PageCut {
    public static let maxPassages = 2000

    public static func sections(_ blocks: [PageBlock]) -> [(heading: String?, text: String)] {
        var out: [(String?, [String])] = []
        var heading: String?
        for b in blocks {
            if b.kind == .h {
                heading = b.text
                out.append((heading, [b.text]))
            } else if out.isEmpty {
                out.append((nil, [b.text]))
            } else {
                out[out.count - 1].1.append(b.text)
            }
        }
        // Each block is one line, so a block with no end mark still ends a sentence (TextCut ends a sentence at a line end).
        return out.map { ($0.0, $0.1.joined(separator: "\n")) }
    }

    /// The passages and true if the page had more than `maxPassages` (state `partial`).
    public static func passages(_ blocks: [PageBlock], headingFront: Bool = false) -> (passages: [Passage], cut: Bool) {
        var out: [Passage] = []
        for s in sections(blocks) {
            for p in TextCut.passages(s.text, startPosition: out.count) {
                var q = p
                if headingFront, let h = s.heading, !p.text.hasPrefix(h) { q.text = h + " · " + p.text }
                out.append(q)
            }
        }
        if out.count > maxPassages { return (Array(out.prefix(maxPassages)), true) }
        return (out, false)
    }
}

/// The bench of E12 (spec section 8): the variants of the main text rule on the development pages, and the one run
/// on the sealed holdout. It prints counts and shares only.
///
/// Folder layout (the same for `pages-dev` and `pages-holdout`): `blocks/<page>.json` (from the read on the Mac),
/// `labels/<page>.tsv`, `labels/pages.tsv` or `pages.tsv` (kinds), `questions*.tsv`.
public final class PageBench {
    public struct PageScore: Sendable {
        public var page: String
        public var found: Double
        public var noise: Double
        public var words: Int
        public var noText: Bool
    }

    public struct Labels: Sendable {
        public var main: [String: Int] = [:]
        public var neutral: [String: Int] = [:]
        public var mainLines: [String] = []
    }

    public struct Question: Sendable { public var page: String; public var other: Bool; public var words: String }

    let folder: URL
    let corpus: BenchFixtures?
    let embedder: Embedder
    public var progress: (String) -> Void = { print($0) }

    public init(folder: URL, corpus: BenchFixtures?, embedder: Embedder) {
        self.folder = folder
        self.corpus = corpus
        self.embedder = embedder
    }

    // MARK: - Data

    public static func multiset(_ s: String) -> [String: Int] {
        var m: [String: Int] = [:]
        for w in WebPageText.words(s) { m[w, default: 0] += 1 }
        return m
    }

    public static func labels(_ url: URL) -> Labels {
        var l = Labels()
        for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "main" { l.main.merge(multiset(parts[1]), uniquingKeysWith: +); l.mainLines.append(parts[1]) }
            if parts[0] == "neutral" { l.neutral.merge(multiset(parts[1]), uniquingKeysWith: +) }
        }
        return l
    }

    /// Found and noise share of a kept text (spec 7.3).
    public static func score(_ text: String, _ l: Labels) -> (found: Double, noise: Double) {
        let kept = multiset(text)
        let mainTotal = l.main.values.reduce(0, +)
        let hit = l.main.reduce(0) { $0 + min($1.value, kept[$1.key] ?? 0) }
        let keptTotal = kept.values.reduce(0, +)
        var rest = kept
        for (w, n) in l.main.merging(l.neutral, uniquingKeysWith: +) { rest[w] = max(0, (rest[w] ?? 0) - n) }
        let noise = keptTotal == 0 ? 0 : Double(rest.values.reduce(0, +)) / Double(keptTotal)
        return (mainTotal == 0 ? 0 : Double(hit) / Double(mainTotal), noise)
    }

    var source: PageFixtureSource { PageFixtureSource(folder: folder.appendingPathComponent("blocks")) }

    public var pages: [String] { source.names }

    func label(_ page: String) -> Labels { Self.labels(folder.appendingPathComponent("labels/\(page).tsv")) }

    /// The kind of each page, from `labels/pages.tsv` or `pages.tsv` (first column the page, second the kind).
    func kinds() -> [String: String] {
        var out: [String: String] = [:]
        for name in ["labels/pages.tsv", "pages.tsv"] {
            let url = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").dropFirst() {
                let f = line.split(separator: "\t").map(String.init)
                if f.count >= 2 { out[f[0]] = f[1] }
            }
        }
        return out
    }

    func questions(_ file: String) -> [Question] {
        let url = folder.appendingPathComponent(file)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard let head = lines.first else { return [] }
        lines.removeFirst()
        let pi = head.firstIndex(of: "page") ?? 1, oi = head.firstIndex(of: "other_words") ?? 2, qi = head.firstIndex(of: "question") ?? 3
        return lines.filter { $0.count > max(pi, oi, qi) }.map { Question(page: $0[pi], other: $0[oi] == "1", words: $0[qi]) }
    }

    // MARK: - Scores

    public func scores(_ variant: MainText.Variant) -> [PageScore] {
        pages.compactMap { p in
            guard let page = source.page(p) else { return nil }
            let r = MainText.select(page.blocks, variant: variant)
            let s = Self.score(r.blocks.map(\.text).joined(separator: "\n"), label(p))
            return PageScore(page: p, found: s.found, noise: s.noise, words: r.words, noText: r.noText)
        }
    }

    /// The search: the first 3 of the merged list of keywords and numbers, as in the phase 2 bench. The index has
    /// the passages of the corpus documents and of the pages. `texts` gives the kept blocks of each page.
    public func search(_ questions: [Question], texts: [String: [PageBlock]], headingFront: Bool,
                       extra: [String: [PageBlock]] = [:]) throws -> (hits: Int, other: Int, hitsOther: Int) {
        var keys: [String] = []
        var entries: [String] = []
        for d in corpus?.docs ?? [] {
            for p in TextCut.passages(d.text) { keys.append("doc:" + d.key); entries.append(p.text) }
        }
        for (page, blocks) in texts.merging(extra, uniquingKeysWith: { a, _ in a }).sorted(by: { $0.key < $1.key }) {
            for p in PageCut.passages(blocks, headingFront: headingFront).passages { keys.append(page); entries.append(p.text) }
        }
        var vecs: [[Float]] = []
        for start in stride(from: 0, to: entries.count, by: 16) {
            vecs += try embedder.embed(Array(entries[start..<min(entries.count, start + 16)]), kind: .passage).map(Vectors.normalized)
        }
        let db = try SQLite(path: ":memory:")
        let kw = try KeywordIndex(db: db, table: "page_bench_fts")
        for (i, t) in entries.enumerated() { try kw.add(Int64(i + 1), t) }
        var hits = 0, other = 0, hitsOther = 0
        for q in questions {
            let kwList = Fusion.unique(kw.search(q.words, limit: 50).map { keys[Int($0) - 1] })
            let qv = Vectors.normalized(try embedder.embed([q.words], kind: .query)[0])
            let s = vecs.map { Vectors.dot($0, qv) }
            let order = vecs.indices.sorted { s[$0] > s[$1] }
            let vecList = Fusion.unique(order.prefix(80).map { keys[$0] })
            let ok = Fusion.merge([kwList, vecList]).prefix(3).contains(q.page)
            if ok { hits += 1 }
            if q.other { other += 1; if ok { hitsOther += 1 } }
        }
        return (hits, other, hitsOther)
    }

    func kept(_ variant: MainText.Variant) -> [String: [PageBlock]] {
        var out: [String: [PageBlock]] = [:]
        for p in pages { if let page = source.page(p) { out[p] = MainText.select(page.blocks, variant: variant).blocks } }
        return out
    }

    /// The main lines of the labels as blocks: the ceiling of spec 8.1.
    func ceiling() -> [String: [PageBlock]] {
        var out: [String: [PageBlock]] = [:]
        for p in pages { out[p] = label(p).mainLines.map { PageBlock($0) } }
        return out
    }

    static func f(_ x: Double) -> String { String(format: "%.3f", x) }

    func summary(_ name: String, _ s: [PageScore]) {
        let found90 = s.filter { $0.found >= 0.90 }.count
        let noise25 = s.filter { $0.noise <= 0.25 }.count
        let medFound = s.map(\.found).sorted()[s.count / 2]
        let medNoise = s.map(\.noise).sorted()[s.count / 2]
        progress("\(name): found >= 0.90 on \(found90) of \(s.count), noise <= 0.25 on \(noise25) of \(s.count), median found \(Self.f(medFound)), median noise \(Self.f(medNoise)), no_text \(s.filter(\.noText).count)")
    }

    // MARK: - Runs

    /// The development run: each variant, with and without the heading in front of the passages. The selection:
    /// the best search number; with equal numbers, the lower median noise share.
    @discardableResult
    public func development(questionsFile: String = "questions-dev.tsv") throws -> (variant: MainText.Variant, headingFront: Bool) {
        let qs = questions(questionsFile)
        progress("Pages \(pages.count), questions \(qs.count), corpus documents \(corpus?.docs.count ?? 0), embedder \(embedder.id)")
        var best: (MainText.Variant, Bool, Int, Double)?
        for v in MainText.Variant.allCases {
            let s = scores(v)
            summary("Variant \(v.rawValue)", s)
            let medNoise = s.map(\.noise).sorted()[s.count / 2]
            for hf in [false, true] {
                let r = try search(qs, texts: kept(v), headingFront: hf)
                progress("Variant \(v.rawValue), heading in front \(hf ? "yes" : "no"): search \(r.hits) of \(qs.count) (other words \(r.hitsOther) of \(r.other))")
                if best == nil || r.hits > best!.2 || (r.hits == best!.2 && medNoise < best!.3) { best = (v, hf, r.hits, medNoise) }
            }
        }
        let c = try search(qs, texts: ceiling(), headingFront: false)
        progress("Ceiling (main lines of the labels): search \(c.hits) of \(qs.count)")
        for p in scores(.full) where p.found < 0.9 || p.noise > 0.25 {
            progress("  \(p.page) found \(Self.f(p.found)) noise \(Self.f(p.noise)) words \(p.words)")
        }
        let sel = best!
        progress("Selected: variant \(sel.0.rawValue), heading in front \(sel.1 ? "yes" : "no")")
        return (sel.0, sel.1)
    }

    /// The one run on a sealed set: counts only, and the numbers by kind of page. `devPages` adds the kept
    /// development pages to the store, as spec 8.1 asks.
    public func final(variant: MainText.Variant, headingFront: Bool, questionsFile: String = "questions.tsv",
                      devPages: PageBench? = nil) throws {
        let s = scores(variant)
        summary("Holdout, variant \(variant.rawValue)", s)
        let kinds = kinds()
        var byKind: [String: [PageScore]] = [:]
        for p in s { byKind[kinds[p.page] ?? "-", default: []].append(p) }
        for (k, list) in byKind.sorted(by: { $0.key < $1.key }) {
            progress("  kind \(k): pages \(list.count), found >= 0.90 on \(list.filter { $0.found >= 0.9 }.count), noise <= 0.25 on \(list.filter { $0.noise <= 0.25 }.count)")
        }
        let qs = questions(questionsFile)
        let extra = devPages.map { $0.kept(variant) } ?? [:]
        let r = try search(qs, texts: kept(variant), headingFront: headingFront, extra: extra)
        progress("Search: correct page in the first 3 for \(r.hits) of \(qs.count) (other words \(r.hitsOther) of \(r.other))")
        let c = try search(qs, texts: ceiling(), headingFront: headingFront, extra: extra)
        progress("Ceiling: \(c.hits) of \(qs.count)")
    }
}
