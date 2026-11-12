import Foundation

/// The model of the request flags: the sentence score, the message score, the variant and the threshold.
/// `RequestWeights.swift` holds the fitted copy, made from `build-a.jsonl` and `design-a.jsonl` by `earshot-pa --flags-bench <mail folder>
/// --write-weights <file>`. It comes from made-up data only.
public struct RequestModel: Codable, Equatable, Sendable {
    public var variant: String
    public var threshold: Double
    public var sentence: Logistic
    public var message: Logistic
    /// The middle sentence score for the feature "count above middle".
    public var middle: Double

    public static var fitted: RequestModel? {
        try? JSONDecoder().decode(RequestModel.self, from: Data(RequestWeights.json.utf8))
    }

    /// The sentence scores, the best sentence and the message score. Variant A uses the points by hand.
    /// `known` is true if the sender wrote to the owner before and that mail passed gate 1.
    public func score(_ m: MailMessage, _ p: RequestFeatures.Prepared, owner: Set<String>, ownerAddresses: Set<String>,
                      known: Bool = true) -> (best: Int?, score: Double) {
        if p.gate != nil { return (nil, -99) }
        if variant == "A" {
            let s = p.sentences.map { RequestFeatures.handScore($0.f) }
            guard let b = s.indices.max(by: { s[$0] < s[$1] }) else { return (nil, -99) }
            return (b, s[b] - (p.org && !known ? 1 : 0))
        }
        let s = p.sentences.map { sentence.p($0.f) }
        let b = s.indices.max(by: { s[$0] < s[$1] })
        guard b != nil else { return (nil, -99) }
        let x = RequestFeatures.messageFeatures(m, p, best: b, sentenceScores: s, owner: owner, ownerAddresses: ownerAddresses,
                                                middle: middle, known: known)
        return (b, message.p(x))
    }
}

/// The bench of experiment E11 (8.5): `earshot-pa --flags-bench <mail fixtures folder> [--embedder <name>]
/// [--final <variant>:<threshold>] [--write-weights <file>]`. With no `--final`, it fits on train and prints the dev
/// table. With `--final`, it runs the holdout one time and prints 4 counts only. It reads only made-up fixtures.
public final class FlagBench {
    public struct Labeled {
        public var m: MailMessage
        public var request: Bool
        public var sentences: Set<String>
        /// The sender wrote before in this set (an earlier date) and that mail passed gate 1.
        public var known = true
        /// A note of the owner, not a mail: no bulk filter and no sender gate.
        public var note = false
    }

    public static let owner: Set<String> = ["maya", "rao"]
    public static let ownerAddresses: Set<String> = ["maya.rao@example.com"]
    /// The owner of the data: the made-up owner by default. `--items` can set another.
    public var owner = FlagBench.owner
    public var ownerAddresses = FlagBench.ownerAddresses
    let folder: URL
    let embedder: Embedder?
    public var out: (String) -> Void = { print($0) }
    let reader: TimeReader

    public init(folder: URL, embedder: Embedder?) {
        self.folder = folder
        self.embedder = embedder
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        reader = TimeReader(calendar: cal)
    }

    public func load(_ name: String) throws -> [Labeled] {
        let mails = try FixtureMail.read(folder.appendingPathComponent(name + ".jsonl"))
        var labels: [String: [String]] = [:]
        for r in try BenchFixtures.rows(folder.appendingPathComponent(name + "-labels.tsv")) where r.count >= 2 && r[0] != "id" {
            labels[r[0]] = r
        }
        var firstPass: [String: Date] = [:]
        for m in mails where BulkFilter.reason(m, owner: ownerAddresses) == nil {
            let a = m.fromAddress.lowercased()
            if firstPass[a].map({ m.date < $0 }) ?? true { firstPass[a] = m.date }
        }
        return mails.map { m in
            let r = labels[m.id] ?? []
            let s = Set([r.count > 3 ? r[3] : "", r.count > 4 ? r[4] : ""].filter { !$0.isEmpty })
            var l = Labeled(m: m, request: r.count > 1 && r[1] == "1", sentences: s)
            l.known = firstPass[m.fromAddress.lowercased()].map { $0 < m.date } ?? false
            l.note = r.count > 2 && r[2] == "note"
            return l
        }
    }

    func timeFound(_ s: String, _ now: Date) -> Bool {
        let r = reader.read(s, now: now, todo: true)
        return r.kind != .none && !r.unsure
    }

    func prepared(_ l: Labeled) -> RequestFeatures.Prepared {
        RequestFeatures.prepared(l.m, owner: owner, ownerAddresses: ownerAddresses, note: l.note) { [self] in timeFound($0, l.m.date) }
    }

    /// Gate 1 (the bulk filter), then gates 2 and 3.
    func passes(_ l: Labeled) -> Bool { gateReason(l) == nil }

    func gateReason(_ l: Labeled) -> String? {
        (l.note ? nil : BulkFilter.reason(l.m, owner: ownerAddresses)) ?? prepared(l).gate
    }

    /// Fits the sentence score and the message score of variant B on the rows.
    public func fitB(_ rows: [Labeled]) -> RequestModel {
        let kept = rows.filter(passes)
        let preps = kept.map(prepared)
        var sx: [[Double]] = [], sy: [Double] = []
        for (l, p) in zip(kept, preps) {
            for s in p.sentences {
                sx.append(s.f)
                sy.append(l.request && l.sentences.contains(s.text) ? 1 : 0)
            }
        }
        let sentence = Logistic.fit(sx, sy, lambda: 0.01, weight: 3)
        var mx: [[Double]] = [], my: [Double] = []
        for (l, p) in zip(kept, preps) {
            let s = p.sentences.map { sentence.p($0.f) }
            let b = s.indices.max(by: { s[$0] < s[$1] })
            var x = RequestFeatures.messageFeatures(l.m, p, best: b, sentenceScores: s, owner: owner,
                                                    ownerAddresses: ownerAddresses, middle: 0.5, known: l.known)
            x.removeLast()
            mx.append(x)
            my.append(l.request ? 1 : 0)
        }
        mx = mx.map { $0 + [1] }
        let message = Logistic.fit(mx, my, lambda: 0.02, weight: 2)
        return RequestModel(variant: "B", threshold: 0.5, sentence: sentence, message: message, middle: 0.5)
    }

    /// The model numbers for variant C: the best sentence, and the subject with the first two sentences.
    func modelVectors(_ rows: [Labeled], best: [Int?], preps: [RequestFeatures.Prepared]) throws -> [[Double]] {
        guard let embedder else { return rows.map { _ in [] } }
        var texts: [String] = []
        for (i, l) in rows.enumerated() {
            texts.append(best[i].map { preps[i].sentences[$0].text } ?? l.m.subject)
            texts.append(([l.m.subject] + preps[i].sentences.prefix(2).map(\.text)).joined(separator: " "))
        }
        var vecs: [[Float]] = []
        for start in stride(from: 0, to: texts.count, by: 16) {
            vecs += try embedder.embed(Array(texts[start..<min(texts.count, start + 16)]), kind: .passage).map(Vectors.normalized)
        }
        return rows.indices.map { i in (vecs[2 * i] + vecs[2 * i + 1]).map(Double.init) }
    }

    struct Scored { var request: Bool; var passed: Bool; var score: Double; var sentenceOK: Bool }

    static func count(_ s: [Scored], _ t: Double) -> (flags: Int, found: Int, falseFlags: Int, sentence: Int) {
        var f = 0, found = 0, wrong = 0, sent = 0
        for x in s where x.passed && x.score >= t {
            f += 1
            if x.request { found += 1; if x.sentenceOK { sent += 1 } } else { wrong += 1 }
        }
        return (f, found, wrong, sent)
    }

    /// The scores of all variants on `test`, with the fit on `train`.
    func scores(train: [Labeled], test: [Labeled]) throws -> [String: [Scored]] {
        let b = fitB(train)
        var out: [String: [Scored]] = [:]
        func bestB(_ l: Labeled, _ p: RequestFeatures.Prepared) -> (Int?, Double) {
            let r = b.score(l.m, p, owner: owner, ownerAddresses: ownerAddresses, known: l.known)
            return (r.best, r.score)
        }
        let tp = test.map(prepared)
        // A
        var a = RequestModel(variant: "A", threshold: 0, sentence: b.sentence, message: b.message, middle: 0.5)
        a.variant = "A"
        out["A"] = zip(test, tp).map { l, p in
            let r = a.score(l.m, p, owner: owner, ownerAddresses: ownerAddresses, known: l.known)
            return Scored(request: l.request, passed: passes(l), score: r.score,
                          sentenceOK: r.best.map { l.sentences.contains(p.sentences[$0].text) } ?? false)
        }
        let testB = zip(test, tp).map { bestB($0, $1) }
        out["B"] = test.indices.map { i in
            Scored(request: test[i].request, passed: passes(test[i]), score: testB[i].1,
                   sentenceOK: testB[i].0.map { test[i].sentences.contains(tp[i].sentences[$0].text) } ?? false)
        }
        guard embedder != nil else { return out }
        // C and D. C uses the best sentence of B.
        let tr = train.filter(passes)
        let trp = tr.map(prepared)
        let trBest = zip(tr, trp).map { bestB($0, $1).0 }
        let trV = try modelVectors(tr, best: trBest, preps: trp)
        let teV = try modelVectors(test, best: testB.map(\.0), preps: tp)
        let ty = tr.map { $0.request ? 1.0 : 0.0 }
        let c = Logistic.fit(trV, ty, lambda: 0.05, steps: 300, weight: 2)
        out["C"] = test.indices.map { i in
            Scored(request: test[i].request, passed: passes(test[i]), score: c.p(teV[i]),
                   sentenceOK: testB[i].0.map { test[i].sentences.contains(tp[i].sentences[$0].text) } ?? false)
        }
        // D: the score of C inside a 5-fold split on train.
        var oof = Array(repeating: 0.0, count: tr.count)
        for k in 0..<5 {
            let inFold = tr.indices.filter { $0 % 5 == k }
            let fitIdx = tr.indices.filter { $0 % 5 != k }
            let ck = Logistic.fit(fitIdx.map { trV[$0] }, fitIdx.map { ty[$0] }, lambda: 0.05, steps: 300, weight: 2)
            for i in inFold { oof[i] = ck.p(trV[i]) }
        }
        func dx(_ l: Labeled, _ p: RequestFeatures.Prepared, _ cScore: Double) -> [Double] {
            let s = p.sentences.map { b.sentence.p($0.f) }
            let best = s.indices.max(by: { s[$0] < s[$1] })
            var x = RequestFeatures.messageFeatures(l.m, p, best: best, sentenceScores: s, owner: owner,
                                                    ownerAddresses: ownerAddresses, middle: 0.5, known: l.known)
            x.removeLast()
            return x + [cScore, 1]
        }
        let d = Logistic.fit(tr.indices.map { dx(tr[$0], trp[$0], oof[$0]) }, ty, lambda: 0.02, weight: 2)
        out["D"] = test.indices.map { i in
            Scored(request: test[i].request, passed: passes(test[i]), score: d.p(dx(test[i], tp[i], c.p(teV[i]))),
                   sentenceOK: testB[i].0.map { test[i].sentences.contains(tp[i].sentences[$0].text) } ?? false)
        }
        return out
    }

    static func thresholds(_ v: String) -> [Double] {
        v == "A" ? stride(from: -2.0, through: 10, by: 1).map { $0 } : stride(from: 0.05, through: 0.951, by: 0.05).map { $0 }
    }

    /// The data sets of version 2 (v2 spec, section 5): written by hand by two writers.
    static let setA = "build-a", setB = "design-a"

    /// The two-way table and the selection (v2 spec, 5.4): fit on build-a and measure on design-a, then the reverse.
    /// The best variant and threshold has the most found requests in the two directions together, where each
    /// direction has a false share of 0.20 or less of its flags. On a tie, the simpler variant (A, B, C, D), and in the
    /// same variant the threshold with fewer false flags.
    public func development() throws {
        let a = try load(Self.setA), b = try load(Self.setB)
        let ab = try scores(train: a, test: b), ba = try scores(train: b, test: a)
        out("| Variant | Threshold | Flags A→B | Found A→B (of \(b.filter(\.request).count)) | False A→B | Sentence A→B | Flags B→A | Found B→A (of \(a.filter(\.request).count)) | False B→A | Sentence B→A |")
        out("|---|---|---|---|---|---|---|---|---|---|")
        var best: (v: String, t: Double, found: Int, wrong: Int)?
        for v in ["A", "B", "C", "D"] {
            guard let s1 = ab[v], let s2 = ba[v] else { continue }
            for t in Self.thresholds(v) {
                let c1 = Self.count(s1, t), c2 = Self.count(s2, t)
                out("| \(v) | \(String(format: "%.2f", t)) | \(c1.flags) | \(c1.found) | \(c1.falseFlags) | \(c1.sentence) | \(c2.flags) | \(c2.found) | \(c2.falseFlags) | \(c2.sentence) |")
                func ok(_ c: (flags: Int, found: Int, falseFlags: Int, sentence: Int)) -> Bool {
                    c.flags > 0 && Double(c.falseFlags) <= 0.20 * Double(c.flags)
                }
                let found = c1.found + c2.found, wrong = c1.falseFlags + c2.falseFlags
                // Most found; on a tie the simpler variant (the first in the loop); in the same variant, fewer false flags.
                if ok(c1), ok(c2), found > (best?.found ?? -1) || (found == best?.found && v == best?.v && wrong < best!.wrong) {
                    best = (v, t, found, wrong)
                }
            }
        }
        guard let best else { out("Selected: none"); return }
        out("Selected: \(best.v) at \(String(format: "%.2f", best.t)) (found in the two directions: \(best.found))")
    }

    /// The one run on the second sealed holdout. The fit uses build-a and design-a together. It prints 4 counts only.
    public func final(variant: String, threshold: Double) throws {
        let train = try load(Self.setA) + load(Self.setB), hold = try load("holdout2")
        let s = try scores(train: train, test: hold)
        guard let sc = s[variant] else { out("No variant \(variant)."); return }
        let c = Self.count(sc, threshold)
        out("Holdout 2, \(variant) at \(String(format: "%.2f", threshold)): flags \(c.flags), found \(c.found) of \(hold.filter(\.request).count), false \(c.falseFlags), sentence correct \(c.sentence)")
        let pass = c.found >= 16 && c.falseFlags <= 5 && c.sentence >= 13
        out("Go mark: \(pass ? "PASS" : "FAIL")")
    }

    /// The run on dk's items (v2 spec, section 6), with the shipped model (`RequestWeights`). The labels file has the
    /// columns id, request (1 for an item with a to-do), and kind (`mail` or `note`). It prints counts only.
    public func items(_ name: String) throws {
        guard let model = RequestModel.fitted else { out("No model."); return }
        let rows = try load(name)
        func line(_ title: String, _ rs: [Labeled]) {
            var flags = 0, found = 0, wrong = 0
            for l in rs {
                let p = prepared(l)
                let flag = passes(l) && model.score(l.m, p, owner: owner, ownerAddresses: ownerAddresses, known: l.known).score >= model.threshold
                if flag { flags += 1; if l.request { found += 1 } else { wrong += 1 } }
            }
            let todo = rs.filter(\.request).count
            let share = flags > 0 ? Double(wrong) / Double(flags) : 0
            out("| \(title) | \(rs.count) | \(flags) | \(found) of \(todo) (\(String(format: "%.2f", todo > 0 ? Double(found) / Double(todo) : 0))) | \(wrong) of \(rs.count - todo) | \(String(format: "%.2f", share)) |")
        }
        out("Model: \(model.variant) at \(model.threshold)")
        out("| Items | Count | Flags | Found | False | False share of flags |")
        out("|---|---|---|---|---|---|")
        line("all", rows)
        line("mails", rows.filter { !$0.note })
        line("notes", rows.filter(\.note))
    }

    /// The failure table of a seen set (v2 spec, section 3), for variant A at a threshold: by kind, then each missed
    /// request and each false flag with its features. Use it only on data that is no longer sealed.
    public func analyze(_ name: String, threshold: Double) throws {
        let rows = try load(name)
        var kindOf: [String: String] = [:]
        for r in try BenchFixtures.rows(folder.appendingPathComponent(name + "-labels.tsv")) where r.count >= 3 { kindOf[r[0]] = r[2] }
        var table: [String: (n: Int, flags: Int, found: Int, wrong: Int, req: Int)] = [:]
        var misses: [String] = [], falses: [String] = []
        for l in rows {
            let k = kindOf[l.m.id] ?? "?"
            var t = table[k] ?? (0, 0, 0, 0, 0)
            t.n += 1
            if l.request { t.req += 1 }
            let gate = gateReason(l)
            let pass = gate == nil
            let p = prepared(l)
            let s = p.sentences.map { RequestFeatures.handScore($0.f) }
            let b = s.indices.max(by: { s[$0] < s[$1] })
            let score = (b.map { s[$0] } ?? -99) - (p.org && !l.known ? 1 : 0)
            let flag = pass && score >= threshold
            if flag { t.flags += 1; if l.request { t.found += 1 } else { t.wrong += 1 } }
            table[k] = t
            func feats(_ i: Int) -> String {
                zip(RequestFeatures.sentenceNames, p.sentences[i].f).filter { $0.1 > 0 }.map(\.0).joined(separator: ",")
            }
            if l.request && !flag {
                let li = p.sentences.firstIndex { l.sentences.contains($0.text) }
                misses.append("MISS \(l.m.id) \(k) gate=\(gate ?? "pass") org=\(p.org) best=\(score) [\(b.map { p.sentences[$0].text } ?? "-")] {\(b.map(feats) ?? "")} labeled=\(li.map { String(s[$0]) } ?? "not a candidate") {\(li.map(feats) ?? "")}")
            }
            if flag && !l.request {
                falses.append("FALSE \(l.m.id) \(k) org=\(p.org) known=\(l.known) score=\(score) [\(b.map { p.sentences[$0].text } ?? "-")] {\(b.map(feats) ?? "")}")
            }
        }
        out("| Kind | Messages | Requests | Flags | Found | False |")
        out("|---|---|---|---|---|---|")
        for (k, t) in table.sorted(by: { $0.key < $1.key }) { out("| \(k) | \(t.n) | \(t.req) | \(t.flags) | \(t.found) | \(t.wrong) |") }
        misses.forEach(out)
        falses.forEach(out)
    }

    /// Writes `RequestWeights.swift` with the model of variant A or B fitted on train.
    public func writeWeights(_ file: URL, variant: String, threshold: Double) throws {
        var m = fitB(try load(Self.setA) + load(Self.setB))
        m.variant = variant
        m.threshold = threshold
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(decoding: try enc.encode(m), as: UTF8.self)
        let text = """
        // Made by `earshot-pa --flags-bench Tests/PACoreTests/Fixtures/phase3/mail --write-weights <this file> --variant \(variant) --threshold \(threshold)`.
        // Fitted on the made-up build-a.jsonl and design-a.jsonl, both written by hand. Do not edit by hand.
        enum RequestWeights {
            static let json = #\"\"\"
        \(json)
        \"\"\"#
        }

        """
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
