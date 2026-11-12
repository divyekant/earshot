import XCTest
@testable import PACore

/// The learning of request flags (build spec 8.8) with two made-up owners. All data is made up.
final class FlagLearningTests: XCTestCase {
    func bench() throws -> FlagBench {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "build-a", withExtension: "jsonl", subdirectory: "Fixtures/phase3/mail"))
        return FlagBench(folder: url.deletingLastPathComponent(), embedder: nil)
    }

    struct Row { var x: [Double]; var request: Bool; var time: Bool; var org: Bool }

    /// The best example of each message that passes the gates, under the weights.
    func rows(_ b: FlagBench, _ set: [FlagBench.Labeled], _ w: FlagWeights) -> [Row] {
        set.compactMap { l in
            guard b.passes(l) else { return nil }
            let p = b.prepared(l)
            guard let best = FlagLearning.best(p, known: l.known, weights: w) else { return nil }
            return Row(x: best.x, request: l.request, time: best.x[4] > 0, org: p.org)
        }
    }

    /// Flags and false flags for an owner rule, under the weights.
    func count(_ b: FlagBench, _ set: [FlagBench.Labeled], _ w: FlagWeights, wants: (Row) -> Bool) -> (flags: Int, wrong: Int) {
        let shown = rows(b, set, w).filter { w.value($0.x) >= 0 }
        return (shown.count, shown.filter { !wants($0) }.count)
    }

    func testTwoOwnersLearn() throws {
        let b = try bench()
        let base = FlagWeights.base(threshold: 4)
        let answerSet = try b.load("build-a") + b.load("design-a")
        let testSet = try b.load("holdout2")
        let dev = try b.load("dev")
        let owners: [(String, (Row) -> Bool)] = [
            ("drops all flags of organizations", { !$0.org }),
            ("keeps only flags with a time limit", { $0.time }),
        ]
        let devFoundBase = count(b, dev, base) { $0.request }.flags - count(b, dev, base) { $0.request }.wrong
        for (name, wants) in owners {
            // The owner answers the flags that the base weights show, in the order of the data, mixed from the two sets.
            let shown = rows(b, answerSet, base).filter { base.value($0.x) >= 0 }
            var mixed: [Row] = []
            for i in stride(from: 0, to: shown.count, by: 2) { mixed.append(shown[i]) }
            for i in stride(from: 1, to: shown.count, by: 2) { mixed.append(shown[i]) }
            let answers = mixed.map { (x: $0.x, kept: wants($0)) }
            let learned = try XCTUnwrap(FlagLearning.learn(answers, base: base), "\(name): the guard kept the base weights")
            let before = count(b, testSet, base, wants: wants)
            let after = count(b, testSet, learned, wants: wants)
            let devFound = count(b, dev, learned) { $0.request }.flags - count(b, dev, learned) { $0.request }.wrong
            print("LEARN \(name): answers \(answers.count) (kept \(answers.filter(\.kept).count)); holdout 2 false before \(before.wrong) of \(before.flags), after \(after.wrong) of \(after.flags); dev found before \(devFoundBase), after \(devFound)")
            XCTAssertLessThan(after.wrong, before.wrong, name)
            XCTAssertGreaterThanOrEqual(devFound, devFoundBase - 2, name)
        }
    }

    func testTooFewAnswersKeepBase() {
        let x = Array(repeating: Array(repeating: 0.0, count: FlagWeights.names.count), count: 40)
        XCTAssertNil(FlagLearning.learn(x.map { (x: $0, kept: true) }, base: .base(threshold: 4)))
    }

    func testBaseWeightsEqualHandPoints() {
        let f = RequestFeatures.sentenceFeatures("Could you send me the form by Friday?", owner: ["maya"], timeFound: true)
        let w = FlagWeights.base(threshold: 4)
        XCTAssertEqual(w.value(FlagLearning.example(f, org: false, known: true)), RequestFeatures.handScore(f) - 4)
        XCTAssertEqual(w.value(FlagLearning.example(f, org: true, known: false)), RequestFeatures.handScore(f) - 5)
    }
}
