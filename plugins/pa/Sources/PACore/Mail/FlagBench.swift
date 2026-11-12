import Foundation

/// The model of the request flags: the sentence score, the message score, the variant and the threshold.
/// `RequestWeights.swift` holds the fitted copy, made from `train.jsonl` by `earshot-pa --flags-bench <mail folder>
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
    public func score(_ m: MailMessage, _ p: RequestFeatures.Prepared, owner: Set<String>, ownerAddresses: Set<String>)
        -> (best: Int?, score: Double) {
        if variant == "A" {
            let s = p.sentences.map { RequestFeatures.handScore($0.f) }
            guard let b = s.indices.max(by: { s[$0] < s[$1] }) else { return (nil, -99) }
            return (b, s[b])
        }
        let s = p.sentences.map { sentence.p($0.f) }
        let b = s.indices.max(by: { s[$0] < s[$1] })
        let x = RequestFeatures.messageFeatures(m, p, best: b, sentenceScores: s, owner: owner, ownerAddresses: ownerAddresses,
                                                middle: middle)
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
    }

    public static let owner: Set<String> = ["maya", "rao"]
    public static let ownerAddresses: Set<String> = ["maya.rao@example.com"]
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
        return mails.map { m in
            let r = labels[m.id] ?? []
            let s = Set([r.count > 3 ? r[3] : "", r.count > 4 ? r[4] : ""].filter { !$0.isEmpty })
            return Labeled(m: m, request: r.count > 1 && r[1] == "1", sentences: s)
        }
    }

    func timeFound(_ s: String, _ now: Date) -> Bool {
        let r = reader.read(s, now: now, todo: true)
        return r.kind != .none && !r.unsure
    }

    func prepared(_ l: Labeled) -> RequestFeatures.Prepared {
        RequestFeatures.prepared(l.m, owner: Self.owner) { [self] in timeFound($0, l.m.date) }
    }

    func passes(_ l: Labeled) -> Bool { BulkFilter.reason(l.m, owner: Self.ownerAddresses) == nil }

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
            var x = RequestFeatures.messageFeatures(l.m, p, best: b, sentenceScores: s, owner: Self.owner,
                                                    ownerAddresses: Self.ownerAddresses, middle: 0.5)
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
            let r = b.score(l.m, p, owner: Self.owner, ownerAddresses: Self.ownerAddresses)
            return (r.best, r.score)
        }
        let tp = test.map(prepared)
        // A
        var a = RequestModel(variant: "A", threshold: 0, sentence: b.sentence, message: b.message, middle: 0.5)
        a.variant = "A"
        out["A"] = zip(test, tp).map { l, p in
            let r = a.score(l.m, p, owner: Self.owner, ownerAddresses: Self.ownerAddresses)
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
            var x = RequestFeatures.messageFeatures(l.m, p, best: best, sentenceScores: s, owner: Self.owner,
                                                    ownerAddresses: Self.ownerAddresses, middle: 0.5)
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

    /// The dev table and the selection (8.5): the most found at 4 or fewer false flags; on a tie the simpler variant;
    /// then one step more strict.
    public func development() throws {
        let train = try load("train"), dev = try load("dev")
        let s = try scores(train: train, test: dev)
        out("| Variant | Threshold | Flags | Found | False | Sentence correct |")
        out("|---|---|---|---|---|---|")
        var best: (v: String, i: Int, found: Int)?
        for v in ["A", "B", "C", "D"] {
            guard let sc = s[v] else { continue }
            let ts = Self.thresholds(v)
            for (i, t) in ts.enumerated() {
                let c = Self.count(sc, t)
                out("| \(v) | \(String(format: "%.2f", t)) | \(c.flags) | \(c.found) | \(c.falseFlags) | \(c.sentence) |")
                if c.falseFlags <= 4, c.found > (best?.found ?? -1) { best = (v, i, c.found) }
            }
        }
        guard let best else { out("Selected: none"); return }
        let ts = Self.thresholds(best.v)
        let strict = ts[min(ts.count - 1, best.i + 1)]
        let c = Self.count(s[best.v]!, strict)
        out("Selected: \(best.v) at \(String(format: "%.2f", ts[best.i])), one step more strict: \(String(format: "%.2f", strict))"
            + " (dev: \(c.flags) flags, \(c.found) found, \(c.falseFlags) false, \(c.sentence) sentences correct)")
    }

    /// The one holdout run. It prints 4 counts only.
    public func final(variant: String, threshold: Double) throws {
        let train = try load("train"), hold = try load("holdout")
        let s = try scores(train: train, test: hold)
        guard let sc = s[variant] else { out("No variant \(variant)."); return }
        let c = Self.count(sc, threshold)
        out("Holdout \(variant) at \(String(format: "%.2f", threshold)): flags \(c.flags), found \(c.found) of \(hold.filter(\.request).count), false \(c.falseFlags), sentence correct \(c.sentence)")
        let pass = c.found >= 16 && c.falseFlags <= 5 && c.sentence >= 13
        out("Go mark: \(pass ? "PASS" : "FAIL")")
    }

    /// Writes `RequestWeights.swift` with the model of variant A or B fitted on train.
    public func writeWeights(_ file: URL, variant: String, threshold: Double) throws {
        var m = fitB(try load("train"))
        m.variant = variant
        m.threshold = threshold
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(decoding: try enc.encode(m), as: UTF8.self)
        let text = """
        // Made by `earshot-pa --flags-bench Tests/PACoreTests/Fixtures/phase3/mail --write-weights <this file> --variant \(variant) --threshold \(threshold)`.
        // Fitted on the made-up train.jsonl only. Do not edit by hand.
        enum RequestWeights {
            static let json = #\"\"\"
        \(json)
        \"\"\"#
        }

        """
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
