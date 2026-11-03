import CoreMedia
import Speech
import EarshotCore
import XCTest
@testable import EarshotSpeech

final class PiecesTests: XCTestCase {
    func testPrerollKeepsOnlyTheLimit() {
        var p = Preroll<Int>(limitFrames: 250)
        for i in 0..<10 { p.add(i, frames: 100) }
        // 3 chunks of 100 cover 250; 2 chunks do not.
        XCTAssertEqual(p.drain(), [7, 8, 9])
        XCTAssertEqual(p.frames, 0)
        XCTAssertTrue(p.drain().isEmpty)
    }

    func testPrerollExactLimit() {
        var p = Preroll<Int>(limitFrames: 200)
        for i in 0..<5 { p.add(i, frames: 100) }
        XCTAssertEqual(p.drain(), [3, 4])
    }

    func testPrerollLargeChunkStays() {
        var p = Preroll<Int>(limitFrames: 100)
        p.add(1, frames: 50)
        p.add(2, frames: 500)
        XCTAssertEqual(p.drain(), [2])
    }

    func testPrerollZeroKeepsNothing() {
        var p = Preroll<Int>(limitFrames: 0)
        p.add(1, frames: 10)
        XCTAssertTrue(p.drain().isEmpty)
    }

    // D-11: the feed keeps 3 s, and a normal turn still gets only the last 250 ms.
    func testPrerollDrainLastTakesTheNewestChunks() {
        var p = Preroll<Int>(limitFrames: 3000)
        for i in 0..<40 { p.add(i, frames: 100) }
        XCTAssertEqual(p.drainLast(frames: 250), [37, 38, 39])
        XCTAssertEqual(p.frames, 0)
        XCTAssertTrue(p.drain().isEmpty, "the older chunks are dropped")
    }

    func testPrerollDrainLastLongWakePreroll() {
        var p = Preroll<Int>(limitFrames: 3000)
        for i in 0..<40 { p.add(i, frames: 100) }
        // A wake turn: start 1.4 s back (frames of 100 here), to hear the whole phrase.
        XCTAssertEqual(p.drainLast(frames: 1400), Array(26...39))
    }

    func testPrerollDrainLastWithLessAudio() {
        var p = Preroll<Int>(limitFrames: 3000)
        p.add(1, frames: 100)
        XCTAssertEqual(p.drainLast(frames: 2000), [1], "it gives what it has")
    }

    func testTailPadFrames() {
        XCTAssertEqual(TailPad.frames(sampleRate: 16000), 4800)
        XCTAssertEqual(TailPad.frames(sampleRate: 48000, seconds: 0.25), 12000)
        XCTAssertEqual(TailPad.frames(sampleRate: 16000, seconds: -1), 0)
    }

    func testTranscriptJoin() {
        var j = TranscriptJoin()
        XCTAssertEqual(j.add("ope", isFinal: false), "ope")
        XCTAssertEqual(j.add("open sl", isFinal: false), "open sl")
        XCTAssertEqual(j.add("open slack", isFinal: true), "open slack")
        XCTAssertEqual(j.add(" and", isFinal: false), "open slack and")
        // No final result for the last words: the volatile text stays.
        XCTAssertEqual(j.text, "open slack and")
    }

    // D-11: the pieces keep their audio times, so that the pipeline can remove the wake phrase by time.
    func testTimedTranscript() {
        var j = TimedTranscript()
        let open = TimedWord(text: "open ", start: 0.1, end: 0.4), slack = TimedWord(text: "Slack", start: 0.4, end: 0.8)
        XCTAssertEqual(j.add("open ", words: [open], isFinal: false), "open ")
        XCTAssertEqual(j.add("open Slack", words: [open, slack], isFinal: true), "open Slack")
        let now = TimedWord(text: " now", start: 0.9, end: 1.1)
        XCTAssertEqual(j.add(" now", words: [now], isFinal: false), "open Slack now")
        XCTAssertEqual(j.words, [open, slack, now], "no final result for the last words: the volatile pieces stay")
        XCTAssertEqual(j.add("", words: [], isFinal: true), "open Slack")
        XCTAssertEqual(j.words, [open, slack])
    }

    func testTextWithNoTimesKeepsTheText() {
        var j = TimedTranscript()
        let open = TimedWord(text: "open ", start: 0.1, end: 0.4)
        _ = j.add("open ", words: [open], isFinal: true)
        XCTAssertEqual(j.add("Slack", words: [], isFinal: true), "open Slack", "the text never depends on the times")
        XCTAssertEqual(j.words, [], "the pieces do not cover the text: no times, so the text strip decides")
    }

    func testWordTimesMustFitTheAudio() {
        let a = TimedWord(text: "open ", start: 0.0, end: 0.3), b = TimedWord(text: "Notes", start: 0.3, end: 0.9)
        XCTAssertTrue(TimedTranscript.plausible([], audioSeconds: 0))
        XCTAssertTrue(TimedTranscript.plausible([a, b], audioSeconds: 1.0))
        XCTAssertFalse(TimedTranscript.plausible([b, a], audioSeconds: 1.0), "out of order")
        XCTAssertFalse(TimedTranscript.plausible([a, b], audioSeconds: 0.2), "after the end of the audio")
        let shifted = [a, b].map { TimedWord(text: $0.text, start: $0.start + 100, end: $0.end + 100) }
        XCTAssertFalse(TimedTranscript.plausible(shifted, audioSeconds: 1.0), "another time base")
    }

    #if compiler(>=6.2)
    func testPiecesOfAnAppleResult() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("SpeechTranscriber needs macOS 26") }
        func timed(_ text: String, _ start: Double, _ end: Double) -> AttributedString {
            var a = AttributedString(text)
            a.audioTimeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000),
                                           end: CMTime(seconds: end, preferredTimescale: 1000))
            return a
        }
        var text = AttributedString(" ")
        text += timed("Hey", 0.1, 0.3)
        text += AttributedString(" ")
        text += timed("Atlas,", 0.3, 0.7)
        text += AttributedString(" ")
        text += timed("open", 0.9, 1.2)
        let pieces = AppleSpeechEngine.pieces(text)
        XCTAssertEqual(pieces.map(\.text).joined(), String(text.characters), "the pieces joined give the text")
        XCTAssertEqual(pieces.map(\.text), [" Hey ", "Atlas, ", "open"])
        XCTAssertEqual(pieces.map(\.start), [0.1, 0.3, 0.9])
        XCTAssertEqual(pieces.map(\.end), [0.3, 0.7, 1.2])
        XCTAssertEqual(AppleSpeechEngine.pieces(AttributedString("no times")), [], "no times: no pieces")
    }
    #endif

    func testTextClean() {
        XCTAssertEqual(TextClean.clean("  open \n slack\t now  "), "open slack now")
        XCTAssertEqual(TextClean.clean(""), "")
    }

    func testPartialSchedule() {
        let s = PartialSchedule()
        XCTAssertFalse(s.due(totalFrames: 8000, lastFrames: 0, sampleRate: 16000))       // 0.5 s: too short
        XCTAssertTrue(s.due(totalFrames: 16000, lastFrames: 0, sampleRate: 16000))       // 1 s
        XCTAssertFalse(s.due(totalFrames: 16000, lastFrames: 12000, sampleRate: 16000))  // 0.25 s new
        XCTAssertTrue(s.due(totalFrames: 22400, lastFrames: 16000, sampleRate: 16000))   // 0.4 s new
        XCTAssertFalse(s.due(totalFrames: 16000 * 31, lastFrames: 0, sampleRate: 16000)) // too long
    }
}

final class ResolverTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/m")

    func locator(_ files: [String]) -> ParakeetModelLocator {
        ParakeetModelLocator(folders: [folder],
                             fileExists: { path in files.contains { "/m/\($0)" == path } || path == "/own/model.gguf" },
                             listFiles: { _ in files })
    }

    func testModelNames() {
        XCTAssertTrue(ParakeetModelLocator.isParakeetModel("parakeet-unified-en-0.6b-Q8_0.gguf"))
        XCTAssertTrue(ParakeetModelLocator.isParakeetModel("sub/Parakeet-TDT.GGUF"))
        XCTAssertFalse(ParakeetModelLocator.isParakeetModel("silero-vad.gguf"))
        XCTAssertFalse(ParakeetModelLocator.isParakeetModel("parakeet.bin"))
    }

    func testFindInFolder() {
        let l = locator(["silero.gguf", "parakeet-b.gguf", "parakeet-a.gguf"])
        XCTAssertEqual(l.find(configured: ""), "/m/parakeet-a.gguf")
    }

    func testConfiguredPathWins() {
        let l = locator(["parakeet-a.gguf"])
        XCTAssertEqual(l.find(configured: "/own/model.gguf"), "/own/model.gguf")
        // A configured file that does not exist: no fallback to the folder. The owner chose that file.
        XCTAssertNil(l.find(configured: "/gone.gguf"))
    }

    func testAutoUsesAppleEvenWithTheFile() {
        // Live test 2026-11-02: Parakeet 0.2-2 s per command with the memory full; Apple about 30 ms.
        let r = EngineResolver.resolve(.auto, configuredModel: "", locator: locator(["parakeet-a.gguf"]))
        XCTAssertEqual(r.engine, .apple)
        XCTAssertTrue(r.why.hasPrefix("auto: Apple"))
    }

    func testParakeetChoiceUsesTheFile() {
        let r = EngineResolver.resolve(.parakeet, configuredModel: "", locator: locator(["parakeet-a.gguf"]))
        XCTAssertEqual(r.engine, .parakeet(modelPath: "/m/parakeet-a.gguf"))
        XCTAssertEqual(r.engine.id, "parakeet")
    }

    func testAppleChoiceIgnoresFile() {
        XCTAssertEqual(EngineResolver.resolve(.apple, configuredModel: "", locator: locator(["parakeet-a.gguf"])).engine, .apple)
    }

    func testParakeetChoiceWithNoFileFallsBack() {
        let r = EngineResolver.resolve(.parakeet, configuredModel: "/gone.gguf", locator: locator([]))
        XCTAssertEqual(r.engine, .apple)
        XCTAssertTrue(r.why.contains("using Apple"))
    }

    func testFactoryTypes() {
        var s = EarshotSettings()
        s.engine = .apple
        XCTAssertEqual(SpeechEngines.make(s, locator: locator(["parakeet-a.gguf"])).engine.id.hasPrefix("apple"), true)
        s.engine = .auto
        XCTAssertEqual(SpeechEngines.make(s, locator: locator(["parakeet-a.gguf"])).engine.id.hasPrefix("apple"), true)
        s.engine = .parakeet
        let (e, _) = SpeechEngines.make(s, locator: locator(["parakeet-a.gguf"]))
        XCTAssertEqual(e.id, "apple", "the guarded Parakeet engine reports Apple until Parakeet is loaded")
        XCTAssertTrue(e is AutoSpeechEngine)
    }

    func testAppleEngineForThisMac() {
        let e = AppleSpeech.make(locale: Locale(identifier: "en_US"))
        if #available(macOS 26, *) {
            #if compiler(>=6.2)
            XCTAssertTrue(e is FallbackSpeechEngine, "macOS 26: SpeechTranscriber with dictation as the fallback")
            #else
            XCTAssertTrue(e is DictationEngine)
            #endif
        } else {
            XCTAssertTrue(e is DictationEngine, "before macOS 26: on-device dictation")
        }
    }

    func testDictationOutcome() {
        XCTAssertEqual(try DictationTurn.outcome("hi", NSError(domain: "x", code: 1)).get(), "hi")
        XCTAssertEqual(try DictationTurn.outcome("", NSError(domain: "kAFAssistantErrorDomain", code: 1110)).get(), "")
        XCTAssertThrowsError(try DictationTurn.outcome("", NSError(domain: "x", code: 1)).get())
        XCTAssertEqual(try DictationTurn.outcome("", nil).get(), "")
        let off = NSError(domain: "kAFAssistantErrorDomain", code: 1101,
                          userInfo: [NSLocalizedDescriptionKey: "Siri and Dictation are disabled"])
        XCTAssertThrowsError(try DictationTurn.outcome("", off).get()) { e in
            XCTAssertTrue("\(e)".contains("System Settings > Keyboard"))
        }
    }
}

/// An engine with no audio, for the fallback tests.
final class FakeEngine: SpeechEngine {
    let id: String
    let fails: Bool
    var prepared = false
    var onPartial: (@Sendable (String) -> Void)?
    init(_ id: String, fails: Bool = false) { self.id = id; self.fails = fails }
    func prepare() async throws {
        if fails { throw SpeechError("load failed") }
        prepared = true
    }
    func begin() throws { onPartial?("partial from \(id)") }
    func end() async throws -> Utterance { Utterance(text: "text from \(id)", engine: id, ms: 1) }
}

final class HintEngine: SpeechEngine, PhraseHintControl {
    let id: String
    let fails: Bool
    var hints: [String] = []
    var onPartial: (@Sendable (String) -> Void)?
    init(_ id: String, fails: Bool = false) { self.id = id; self.fails = fails }
    func prepare() async throws { if fails { throw SpeechError("load failed") } }
    func begin() throws {}
    func end() async throws -> Utterance { Utterance(text: "", engine: id, ms: 1) }
    func setPhraseHints(_ phrases: [String]) { hints = phrases }
}

final class FallbackTests: XCTestCase {
    func testPrimaryWorks() async throws {
        let e = FallbackSpeechEngine(primary: FakeEngine("parakeet"), fallback: { FakeEngine("apple") })
        try await e.prepare()
        XCTAssertEqual(e.id, "parakeet")
        XCTAssertNil(e.fallbackReason)
        try e.begin()
        let u = try await e.end()
        XCTAssertEqual(u.engine, "parakeet")
    }

    func testPrimaryFailsUsesFallback() async throws {
        let e = FallbackSpeechEngine(primary: FakeEngine("parakeet", fails: true), fallback: { FakeEngine("apple") })
        let got = Locked<[String]>([])
        e.onPartial = { text in got.mutate { $0.append(text) } }
        try await e.prepare()
        XCTAssertEqual(e.id, "apple")
        XCTAssertEqual(e.fallbackReason, "load failed")
        try e.begin()
        XCTAssertEqual(got.value, ["partial from apple"])
        let u = try await e.end()
        XCTAssertEqual(u.text, "text from apple")
    }

    // D-11: the wake phrase reaches the engine in use, and the fallback engine if it takes over.
    func testPhraseHintsReachTheFallback() async throws {
        let primary = HintEngine("apple", fails: true), fallback = HintEngine("apple-dictation")
        let e = FallbackSpeechEngine(primary: primary, fallback: { fallback })
        e.setPhraseHints(["hey atlas"])
        XCTAssertEqual(primary.hints, ["hey atlas"])
        try await e.prepare()
        XCTAssertEqual(e.id, "apple-dictation")
        XCTAssertEqual(fallback.hints, ["hey atlas"], "the fallback engine gets the hints when it takes over")
        e.setPhraseHints([])
        XCTAssertEqual(fallback.hints, [], "hold mode: no hints")
    }

    func testBothFailThrows() async {
        let e = FallbackSpeechEngine(primary: FakeEngine("p", fails: true), fallback: { FakeEngine("a", fails: true) })
        do {
            try await e.prepare()
            XCTFail("prepare must throw")
        } catch {
            XCTAssertEqual(error as? SpeechError, SpeechError("load failed"))
        }
    }
}

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
}

final class TimingTests: XCTestCase {
    func testStagesAndSummary() {
        var t = SpeechTiming(engine: "parakeet", why: "auto: Parakeet model file found")
        t.tailMs = 0.44; t.waitMs = 12.06; t.decodeMs = 33.33; t.audioMs = 2140; t.idleMs = 61000; t.warmed = true
        XCTAssertEqual(t.stages, ["speech.tail": 0.4, "speech.wait": 12.1, "speech.decode": 33.3])
        XCTAssertEqual(t.summary, "parakeet (auto: Parakeet model file found) audio 2140 ms, idle 61000 ms, warmed")
    }

    func testFactorySetsReason() {
        var s = EarshotSettings()
        s.engine = .apple
        let (e, why) = SpeechEngines.make(s)
        XCTAssertEqual((e as? SpeechTimingReporting)?.reason, why)
        XCTAssertNil((e as? SpeechTimingReporting)?.lastTiming)
    }
}

final class TurnTests: XCTestCase {
    func testNewTurnClearsTheBuffer() {
        let e = ParakeetEngine(modelPath: "/none.gguf", useMicrophone: false)
        e.beginWithoutMicrophone()
        e.feed([Float](repeating: 0.1, count: 16000))
        XCTAssertEqual(e.bufferedFrames, 16000)
        e.beginWithoutMicrophone()
        XCTAssertEqual(e.bufferedFrames, 0, "a new turn must not keep the audio of the last turn")
        e.feed([Float](repeating: 0.1, count: 800))
        XCTAssertEqual(e.bufferedFrames, 800)
    }

    func testEndOfTurnClearsTheBufferAndTheActivity() async {
        let e = ParakeetEngine(modelPath: "/none.gguf", useMicrophone: false)
        e.beginWithoutMicrophone()
        XCTAssertTrue(e.activity.isActive)
        e.feed([Float](repeating: 0.1, count: 1600))
        _ = try? await e.end()   // throws: no model. The buffer and the activity must still be cleared.
        XCTAssertEqual(e.bufferedFrames, 0)
        XCTAssertFalse(e.activity.isActive)
    }

    func testFeedOutsideATurnIsIgnored() {
        let e = ParakeetEngine(modelPath: "/none.gguf", useMicrophone: false)
        e.feed([Float](repeating: 0.1, count: 1600))
        XCTAssertEqual(e.bufferedFrames, 0)
    }
}

final class AutoPolicyTests: XCTestCase {
    let p = AutoPolicy()

    func testStartParakeetOnlyWhenLoadedAndNormal() {
        XCTAssertTrue(p.tryParakeet(loaded: true, pressure: .normal).0)
        XCTAssertFalse(p.tryParakeet(loaded: false, pressure: .normal).0)
        let (start, why) = p.tryParakeet(loaded: true, pressure: .warning)
        XCTAssertFalse(start)
        XCTAssertEqual(why, "apple: memory pressure warning")
        XCTAssertFalse(p.tryParakeet(loaded: true, pressure: .critical).0)
    }

    func testUseParakeetOnlyIfWarmUpWasFast() {
        XCTAssertEqual(p.warmLimit(baselineMs: 10), 120)
        XCTAssertEqual(p.warmLimit(baselineMs: 50), 200)
        XCTAssertTrue(p.useParakeet(warmMs: 25, baselineMs: 20).0)
        let (use, why) = p.useParakeet(warmMs: 900, baselineMs: 20)
        XCTAssertFalse(use)
        XCTAssertTrue(why.contains("weights not in memory"))
        XCTAssertFalse(p.useParakeet(warmMs: nil, baselineMs: 20).0, "a warm-up that is not done means: do not wait for Parakeet")
    }

    func testPressureLevelReads() {
        // The call must work on any Mac. The value depends on the Mac.
        XCTAssertNotNil(MemoryPressureLevel(rawValue: MemoryPressureLevel.current().rawValue))
    }
}
