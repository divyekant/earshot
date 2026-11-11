import EarshotCore
import Foundation
import XCTest
@testable import EarshotInput
@testable import EarshotWake

// E7: the turn recorder keeps the numbers of a turn, and the replay runs the rules on them again, with no audio.
final class TurnReplayTests: XCTestCase {
    let quiet: Float = 0.0005
    let speech: Float = 0.05

    private func make(_ listener: ReplayListener, config: WakeConfig = WakeConfig()) -> (WakeTrigger, ReplaySamples, Box) {
        let source = ReplaySamples()
        let trigger = WakeTrigger(listener: listener, config: config, source: source)
        let box = Box()
        trigger.onRecord = { box.records.append($0) }
        trigger.onStop = { box.events.append("stop") }
        trigger.onCancel = { box.events.append("cancel: \($0)") }
        trigger.onRejected = { _ in box.events.append("rejected") }
        XCTAssertNoThrow(try trigger.start())
        return (trigger, source, box)
    }

    /// Waits until the main queue has the callbacks of the samples so far.
    private func settle(_ box: Box, records: Int) {
        let done = expectation(description: "records")
        func check() {
            if box.records.count >= records { done.fulfill() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: check) }
        }
        DispatchQueue.main.async(execute: check)
        wait(for: [done], timeout: 3)
    }

    func testAWakeTurnReplaysToTheSameEnd() {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        listener.turnProbability = 0.2   // the model hears a pause in the sentence: the turn waits
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(quiet, ms: 300)
        mic.emit(speech, ms: 800)
        mic.emit(quiet, ms: 2600)
        settle(box, records: 1)
        t.stop()
        guard let record = box.records.first else { return XCTFail("no record") }
        XCTAssertEqual(record.kind, .wake)
        XCTAssertEqual(record.outcome, "end")
        XCTAssertEqual(record.matchScore, 0.2)
        XCTAssertEqual(record.trace?.matchStart, 3)
        XCTAssertFalse(record.checks.isEmpty, "the turn model answered at the pause")
        XCTAssertEqual(record.voice?.passed, true)
        XCTAssertGreaterThan(record.turnStart, 0, "the levels start before the turn")
        let replay = TurnReplay.end(of: record)
        XCTAssertEqual(replay.event, .end)
        XCTAssertEqual(replay.end, record.end, "the same rule, quiet time and length as the live turn")
        XCTAssertEqual(replay.checks, record.checks.count)
    }

    func testTheModelEndOfATurnReplays() {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        listener.turnProbability = 0.9
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 800)
        settle(box, records: 1)
        t.stop()
        guard let record = box.records.first else { return XCTFail("no record") }
        XCTAssertEqual(record.end?.rule, .model)
        XCTAssertEqual(TurnReplay.end(of: record).end, record.end)
    }

    func testAFollowUpTurnReplaysToTheSameEnd() {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 500)
        mic.emit(quiet, ms: 800)
        settle(box, records: 1)
        t.openFollowUp()
        mic.emit(quiet, ms: 400)
        mic.emit(speech, ms: 700)
        mic.emit(quiet, ms: 900)
        settle(box, records: 2)
        t.stop()
        let record = box.records[1]
        XCTAssertEqual(record.kind, .followUp)
        XCTAssertNil(record.matchScore, "no phrase in a follow-up turn")
        XCTAssertEqual(record.outcome, "end")
        XCTAssertEqual(TurnReplay.end(of: record).end, record.end)
    }

    func testARejectedWakeKeepsTheLevelsAndTheScores() {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        listener.hit.isOwner = false
        listener.hit.voiceScore = 0.21
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 300)
        settle(box, records: 1)
        t.stop()
        guard let record = box.records.first else { return XCTFail("no record") }
        XCTAssertEqual(record.kind, .rejectedWake)
        XCTAssertEqual(record.wakeVoice, 0.21)
        XCTAssertEqual(record.gate, WakeConfig().voice.gate)
        XCTAssertEqual(record.levels.count, 50, "1 s of 20 ms frames before the wake")
        XCTAssertNotNil(record.trace)
        XCTAssertEqual(box.events, ["rejected"])
        XCTAssertNil(TurnReplay.end(of: record).event, "no turn to replay")
        // The gate on the kept score: a lower gate would open a turn for this match.
        XCTAssertFalse(ReplayMath.passes(record, gate: 0.35))
        XCTAssertTrue(ReplayMath.passes(record, gate: 0.10))
    }

    func testAVoiceDropKeepsItsReason() {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        listener.score = 0.2   // the phrase passed the gate, the whole turn did not
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 800)
        settle(box, records: 1)
        t.stop()
        guard let record = box.records.first else { return XCTFail("no record") }
        XCTAssertTrue(record.outcome.hasPrefix(WakeTrigger.otherVoice))
        XCTAssertEqual(record.voice?.passed, false)
    }

    func testAnotherEndSilenceChangesTheReplay() {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 1500)
        settle(box, records: 1)
        t.stop()
        guard let record = box.records.first else { return XCTFail("no record") }
        var longer = WakeConfig()
        longer.detector.endSilenceMs = 1000
        let live = TurnReplay.end(of: record)
        let replay = TurnReplay.end(of: record, config: longer)
        XCTAssertEqual(replay.end?.endSilenceMs, 1000)
        XCTAssertGreaterThan(replay.endFrame ?? 0, live.endFrame ?? 0)
    }

    func testTheRecordGoesThroughTheFile() throws {
        let listener = ReplayListener()
        listener.hitAfterSamples = 16000
        listener.turnProbability = 0.3
        let (t, mic, box) = make(listener)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 900)
        mic.emit(quiet, ms: 2500)
        settle(box, records: 1)
        t.stop()
        let data = try JSONEncoder().encode(box.records[0])
        let back = try JSONDecoder().decode(TurnRecord.self, from: data)
        XCTAssertEqual(TurnReplay.end(of: back).end, box.records[0].end, "the rounded levels give the same end")
    }
}

// E5, E7: the template match runs again on the kept wake frames, and gives the score of the live match.
final class MatchReplayTests: XCTestCase {
    private func frames(_ count: Int, seed: UInt64) -> [[Float]] {
        var state = seed
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 11) % 2000) / 1000 - 1
        }
        return (0..<count).map { _ in (0..<320).map { _ in next() } }
    }

    private func noisy(_ take: [[Float]], seed: UInt64, amount: Float = 0.3) -> [[Float]] {
        zip(take, frames(take.count, seed: seed)).map { frame, n in zip(frame, n).map { $0 + amount * $1 } }
    }

    func testTheKeptFramesGiveTheLiveScore() throws {
        let phrase = frames(22, seed: 9)
        let templates = (0..<4).map { noisy(phrase, seed: 50 + UInt64($0)) }
        // As in PhraseListener: each frame goes to the matcher and to the ring.
        let live = TemplateMatcher(templates: templates)
        var ring = FrameRing()
        var trace: WakeTrace?
        var match: TemplateMatcher.Match?
        let stream = frames(60, seed: 1) + noisy(phrase, seed: 77) + frames(8, seed: 2)
        for frame in stream {
            let hit = live.push(frame)
            ring.add(frame, score: live.lastScore)
            if let hit, match == nil {
                match = hit
                trace = ring.trace(matchStart: hit.startFrame, matchEnd: hit.endFrame, limit: live.limit)
            }
        }
        let m = try XCTUnwrap(match)
        let t = try XCTUnwrap(trace)
        XCTAssertEqual(t.firstFrame + t.matchStart, m.startFrame)
        let replay = ReplayMath.lowest(t, templates: templates)
        XCTAssertEqual(replay.score, m.score, accuracy: 0.01, "16-bit frames give the same score")
        XCTAssertEqual(replay.frame, t.matchEnd, "the lowest score is at the end of the match")
        // The kept score of the matching frame is the score of the live match.
        XCTAssertEqual(t.scores[t.matchEnd] ?? -1, m.score, accuracy: 0.001)
    }
}

// E7: the kept turns on the owner's Mac. Set EARSHOT_TURNS to the turns folder (and EARSHOT_VOICE to voice.json for
// the template match). It prints a summary with numbers only. CI skips it.
final class KeptTurnsReport: XCTestCase {
    func testKeptTurns() throws {
        guard let path = ProcessInfo.processInfo.environment["EARSHOT_TURNS"] else {
            throw XCTSkip("Set EARSHOT_TURNS to the turns folder of earshot.")
        }
        let records = TurnStore.read(folder: URL(fileURLWithPath: path))
        var templates: [[[Float]]] = []
        if let voice = ProcessInfo.processInfo.environment["EARSHOT_VOICE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: voice)) {
            let book = (try? JSONDecoder().decode(VoiceBook.self, from: data))
                ?? (try? JSONDecoder().decode(VoiceProfile.self, from: data)).map { VoiceBook(profiles: [$0]) }
            let micID = ProcessInfo.processInfo.environment["EARSHOT_MIC"]
            if let profile = book?.profile(forMic: micID) {
                templates = (profile.templates ?? []).map(WakeTemplates.unpack).filter { !$0.isEmpty }
            }
        }
        print(ReplayMath.report(records, templates: templates))
    }
}

/// The sums of the replay report. Numbers only: no text of the turns.
enum ReplayMath {
    /// True if the voice of the phrase reaches this gate.
    static func passes(_ record: TurnRecord, gate: Double) -> Bool { (record.wakeVoice ?? -1) >= gate }

    /// The lowest score of the templates over the kept frames, and its frame index.
    static func lowest(_ trace: WakeTrace, templates: [[[Float]]]) -> (score: Double, frame: Int) {
        guard let packed = trace.frames else { return (.infinity, -1) }
        let matcher = TemplateMatcher(templates: templates)
        var best = (score: Double.infinity, frame: -1)
        for (i, frame) in WakeTemplates.unpack(packed).enumerated() {
            _ = matcher.push(frame)
            if matcher.lastScore < best.score { best = (matcher.lastScore, i) }
        }
        return best
    }

    /// The mean level of the frames of the match, in dB. One encoder frame is 40 ms, two level frames.
    static func matchLevel(_ record: TurnRecord) -> Double? {
        guard let trace = record.trace, record.levelFrameMs > 0 else { return nil }
        let framesPerEncoder = 40 / record.levelFrameMs
        // The levels end at the wake; the trace ends at the wake too.
        let fromEnd = Double(trace.scores.count - trace.matchStart) * framesPerEncoder
        let toEnd = Double(trace.scores.count - 1 - trace.matchEnd) * framesPerEncoder
        let first = max(0, record.turnStart - Int(fromEnd)), last = max(first, record.turnStart - Int(toEnd))
        let values = record.levels[first..<min(last, record.levels.count)].compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func quantiles(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "none" }
        let s = values.sorted()
        func q(_ p: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * p))] }
        return String(format: "n %d, min %.2f, p25 %.2f, median %.2f, p75 %.2f, max %.2f", s.count, q(0), q(0.25), q(0.5), q(0.75), q(1))
    }

    static func report(_ records: [TurnRecord], templates: [[[Float]]]) -> String {
        var lines = ["Kept turns: \(records.count)"]
        for kind in [TurnRecord.Kind.wake, .followUp, .rejectedWake] {
            let some = records.filter { $0.kind == kind }
            lines.append("\(kind.rawValue): \(some.count)")
        }
        let wakes = records.filter { $0.kind == .wake }
        let rejected = records.filter { $0.kind == .rejectedWake }
        lines.append("owner wakes, match score: " + quantiles(wakes.compactMap(\.matchScore)))
        lines.append("owner wakes, phrase voice: " + quantiles(wakes.compactMap(\.wakeVoice)))
        lines.append("rejected wakes, match score: " + quantiles(rejected.compactMap(\.matchScore)))
        lines.append("rejected wakes, worst part: " + quantiles(rejected.compactMap(\.matchWorst)))
        lines.append("rejected wakes, phrase voice: " + quantiles(rejected.compactMap(\.wakeVoice)))
        lines.append("rejected wakes, frames since the encoder reset: "
                     + quantiles(rejected.compactMap { $0.trace.map { Double($0.firstFrame + $0.matchStart) } }))
        lines.append("owner wakes, frames since the encoder reset: "
                     + quantiles(wakes.compactMap { $0.trace.map { Double($0.firstFrame + $0.matchStart) } }))
        lines.append("rejected wakes, match level dB: " + quantiles(rejected.compactMap(matchLevel)))
        lines.append("owner wakes, match level dB: " + quantiles(wakes.compactMap(matchLevel)))
        lines.append("rejected wakes, floor dB: " + quantiles(rejected.map(\.floorDb)))
        let gaps = zip(rejected.dropFirst(), rejected).map { $0.at.timeIntervalSince($1.at) }.filter { $0 < 60 }
        lines.append("seconds between rejected wakes (under 60 s): " + quantiles(gaps))
        for gate in [0.35, 0.25, 0.20, 0.15, 0.10] {
            lines.append(String(format: "gate %.2f: %d of %d rejected wakes would open a turn, %d of %d owner wakes pass",
                                gate, rejected.filter { passes($0, gate: gate) }.count, rejected.count,
                                wakes.filter { passes($0, gate: gate) }.count, wakes.count))
        }
        if !templates.isEmpty {
            let again = rejected.compactMap { $0.trace }.filter { $0.frames != nil }.map { lowest($0, templates: templates).score }
            lines.append("rejected wakes, replayed score with the current templates: " + quantiles(again))
            for limit in [0.33, 0.30, 0.27, 0.25] {
                lines.append(String(format: "limit %.2f: %d of %d kept rejected matches still match", limit,
                                    again.filter { $0 < limit }.count, again.count))
            }
        }
        // The end of each turn, replayed with the live rules.
        let turns = records.filter { $0.kind != .rejectedWake && $0.end != nil }
        let same = turns.filter { TurnReplay.end(of: $0).end == $0.end }.count
        lines.append("turns that replay to the same end: \(same) of \(turns.count)")
        var ends: [String: Int] = [:]
        for t in turns { ends[t.end!.rule.rawValue, default: 0] += 1 }
        lines.append("end rules: " + ends.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        var outcomes: [String: Int] = [:]
        for r in records where r.kind != .rejectedWake {
            let key = r.outcome.split(separator: "(").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? r.outcome
            outcomes[key, default: 0] += 1
        }
        lines.append("turn outcomes: " + outcomes.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}

final class Box: @unchecked Sendable {
    var records: [TurnRecord] = []
    var events: [String] = []
}

/// A fake microphone: 16 kHz samples of one level, in blocks of 100 ms.
final class ReplaySamples: SampleSource {
    var onSamples: (@Sendable ([Float]) -> Void)?
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws { self.onSamples = onSamples }
    func stop() { onSamples = nil }
    func emit(_ level: Float, ms: Int) {
        let block: [Float] = (0..<1600).map { $0 % 2 == 0 ? level : -level }
        for _ in 0..<(ms / 100) { onSamples?(block) }
    }
}

/// A fake wake listener: one hit after `hitAfterSamples`, with a trace of made-up frame scores.
final class ReplayListener: WakeListener, @unchecked Sendable {
    var hitAfterSamples: Int?
    var hit = WakeHit(phrase: "hey jarvis", prerollSeconds: 1.4, phraseEndSeconds: 0.4, voiceScore: 0.8, isOwner: true,
                      matchScore: 0.2, matchWorst: 0.3)
    var score: Double? = 0.8
    var voiceThreshold = 0.35
    var turnProbability: Double?
    private var fed = 0
    private var trace: WakeTrace?
    func feed(_ samples: [Float]) -> WakeHit? {
        fed += samples.count
        if let n = hitAfterSamples, fed >= n {
            hitAfterSamples = nil
            trace = WakeTrace(frames: nil, scores: [0.9, 0.5, nil, 0.3, 0.2, 0.25], firstFrame: 40, matchStart: 3,
                              matchEnd: 4, limit: 0.33)
            return hit
        }
        return nil
    }
    func voiceScore(_ samples: [Float]) -> Double? { score }
    func voiceCheck(_ samples: [Float]) -> VoiceCheck? {
        score.map { VoiceCheck(score: $0, seconds: Double(samples.count) / 16000) }
    }
    func reset() { fed = 0 }
    func turnScore(_ samples: [Float]) -> Double? { turnProbability }
    func takeTrace() -> WakeTrace? { defer { trace = nil }; return trace }
}
