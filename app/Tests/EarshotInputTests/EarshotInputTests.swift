import EarshotCore
import XCTest
@testable import EarshotInput

// R-ON-4: the hold key.
final class KeyHoldTests: XCTestCase {
    let rOpt: UInt = 0x40 | ModifierBits.option
    let lShift: UInt = 0x02 | ModifierBits.shift

    func ev(_ k: KeyEvent.Kind, _ code: UInt16, _ flags: UInt = 0, _ t: Double, rep: Bool = false) -> KeyEvent {
        KeyEvent(k, code: code, flags: flags, isRepeat: rep, time: t)
    }

    func testRightOptionHoldStartsAndStops() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, rOpt, 0)), .start)
        XCTAssertTrue(k.active)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, 0, 1.0)), .stop)
        XCTAssertFalse(k.active)
    }

    func testLeftOptionDoesNotTriggerRightOption() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertNil(k.handle(ev(.flagsChanged, 58, 0x20 | ModifierBits.option, 0)))
        XCTAssertNil(k.handle(ev(.flagsChanged, 58, 0, 1)))
    }

    func testTapIsCancelled() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, rOpt, 0)), .start)
        guard case .cancel = k.handle(ev(.flagsChanged, 61, 0, 0.05)) else { return XCTFail("tap must cancel") }
    }

    func testTypedCharacterCancels() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, rOpt, 0)), .start)
        guard case .cancel = k.handle(ev(.keyDown, 14, rOpt, 0.3)) else { return XCTFail("Option+E must cancel") }
        XCTAssertNil(k.handle(ev(.keyUp, 14, rOpt, 0.4)))
        XCTAssertNil(k.handle(ev(.flagsChanged, 61, 0, 0.5)), "release after a cancel does nothing")
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, rOpt, 1)), .start, "the next press works")
    }

    func testOtherModifierHeldBlocksStart() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertNil(k.handle(ev(.flagsChanged, 56, lShift, 0)))
        XCTAssertNil(k.handle(ev(.flagsChanged, 61, lShift | rOpt, 0.1)))
        XCTAssertNil(k.handle(ev(.flagsChanged, 61, lShift, 0.5)))
    }

    func testOtherModifierDuringHoldCancels() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, rOpt, 0)), .start)
        guard case .cancel = k.handle(ev(.flagsChanged, 56, rOpt | lShift, 0.3)) else { return XCTFail() }
        XCTAssertNil(k.handle(ev(.flagsChanged, 56, rOpt, 0.4)))
        XCTAssertNil(k.handle(ev(.flagsChanged, 61, 0, 0.5)))
    }

    func testCapsLockDoesNotBlock() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 61, rOpt | ModifierBits.capsLock, 0)), .start)
    }

    func testFnKey() {
        var k = KeyHold(code: 63, modifierOnly: true)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 63, ModifierBits.function, 0)), .start)
        XCTAssertEqual(k.handle(ev(.flagsChanged, 63, 0, 1)), .stop)
    }

    func testNormalKeyWithModifiers() {
        // Control + F5 (code 96).
        var k = KeyHold(code: 96, modifierOnly: false, modifiers: ModifierBits.control)
        XCTAssertNil(k.handle(ev(.keyDown, 96, 0, 0)), "F5 without Control does nothing")
        XCTAssertEqual(k.handle(ev(.keyDown, 96, ModifierBits.control | 0x01, 0.1)), .start)
        XCTAssertNil(k.handle(ev(.keyDown, 96, ModifierBits.control, 0.2, rep: true)), "repeats do nothing")
        XCTAssertEqual(k.handle(ev(.keyUp, 96, 0, 1)), .stop)
    }

    func testResetCancelsOpenHold() {
        var k = KeyHold(code: 61, modifierOnly: true)
        XCTAssertNil(k.reset())
        _ = k.handle(ev(.flagsChanged, 61, rOpt, 0))
        guard case .cancel = k.reset() else { return XCTFail() }
        XCTAssertFalse(k.active)
    }

    func testTriggerUsesSettings() {
        let t = HoldKeyTrigger(settings: EarshotSettings())
        var log: [String] = []
        t.onStart = { log.append("start") }
        t.onStop = { log.append("stop") }
        t.onCancel = { _ in log.append("cancel") }
        t.receive(KeyEvent(.flagsChanged, code: 61, flags: rOpt, time: 0))
        XCTAssertTrue(t.isHolding)
        t.receive(KeyEvent(.flagsChanged, code: 61, flags: 0, time: 0.8))
        t.receive(KeyEvent(.flagsChanged, code: 61, flags: rOpt, time: 1))
        t.receive(KeyEvent(.flagsChanged, code: 61, flags: 0, time: 1.01))
        XCTAssertEqual(log, ["start", "stop", "start", "cancel"])
    }

    func testCancelFallsBackToStopWithoutHandler() {
        let t = HoldKeyTrigger(settings: EarshotSettings())
        var log: [String] = []
        t.onStart = { log.append("start") }
        t.onStop = { log.append("stop") }
        t.receive(KeyEvent(.flagsChanged, code: 61, flags: rOpt, time: 0))
        t.receive(KeyEvent(.flagsChanged, code: 61, flags: 0, time: 0.01))
        XCTAssertEqual(log, ["start", "stop"])
    }
}

// R-ON-1: speech detection and end of turn.
final class SpeechDetectorTests: XCTestCase {
    /// Feeds `ms` of a level. Returns the events.
    func run(_ d: inout SpeechDetector, _ db: Double, ms: Double) -> [SpeechEvent] {
        var out: [SpeechEvent] = []
        for _ in 0..<Int(ms / d.config.frameMs) { if let e = d.feed(db: db) { out.append(e) } }
        return out
    }

    func testCommandIsOneTurn() {
        var d = SpeechDetector()
        XCTAssertEqual(run(&d, -65, ms: 1000), [], "room noise")
        XCTAssertEqual(run(&d, -25, ms: 60), [.start], "starts after 60 ms of speech")
        XCTAssertEqual(run(&d, -25, ms: 600), [])
        XCTAssertEqual(run(&d, -65, ms: 300), [], "a short pause keeps the turn")
        XCTAssertEqual(run(&d, -25, ms: 500), [])
        XCTAssertEqual(run(&d, -65, ms: 560), [.end], "ends after 550 ms of quiet")
    }

    func testShortSoundIsDropped() {
        var d = SpeechDetector()
        _ = run(&d, -65, ms: 500)
        var events = run(&d, -20, ms: 100)
        events += run(&d, -65, ms: 600)
        XCTAssertEqual(events.first, .start)
        guard case .drop = events.last else { return XCTFail("a cough must be dropped") }
    }

    func testSteadyNoiseLiftsTheFloor() {
        var d = SpeechDetector()
        _ = run(&d, -65, ms: 500)
        // A fan starts at -40 dB. It opens one turn at most; the floor then follows it.
        let events = run(&d, -40, ms: 30000)
        XCTAssertLessThanOrEqual(events.filter { $0 == .start }.count, 1)
        XCTAssertGreaterThan(d.floorDb, -45)
        XCTAssertFalse(d.inTurn)
        // Speech above the fan still starts a turn.
        XCTAssertEqual(run(&d, -15, ms: 60), [.start])
    }

    func testLongTurnStops() {
        var d = SpeechDetector()
        _ = run(&d, -65, ms: 500)
        // Changing loud speech, as from a TV: the floor stays low because the level moves.
        var events: [SpeechEvent] = []
        for i in 0..<1000 { if let e = d.feed(db: i % 2 == 0 ? -20 : -24) { events.append(e) } }
        XCTAssertEqual(events.first, .start)
        XCTAssertTrue(events.contains { if case .drop = $0 { return true }; return false })
    }

    func testQuietSpeechBelowMinimumIsIgnored() {
        var d = SpeechDetector()
        XCTAssertEqual(run(&d, -90, ms: 1000), [])
        XCTAssertEqual(run(&d, -55, ms: 500), [], "below -50 dB is not speech")
    }

    func testTrackOpensNoTurn() {
        var d = SpeechDetector()
        for _ in 0..<50 { d.track(db: -65) }
        for _ in 0..<50 { XCTAssertTrue(d.track(db: -25)) }
        XCTAssertFalse(d.inTurn, "between wake phrases, speech alone opens no turn (D-11)")
    }

    func testWakeTurnWaitsForTheCommand() {
        var d = SpeechDetector()
        _ = run(&d, -65, ms: 500)
        d.open(heardSpeech: false, quietMs: 0, graceMs: 2000)
        XCTAssertEqual(run(&d, -65, ms: 1000), [], "a pause after the phrase keeps the turn")
        XCTAssertEqual(run(&d, -25, ms: 400), [])
        XCTAssertEqual(run(&d, -65, ms: 560), [.end], "the normal end silence after the command")
    }

    func testWakeTurnWithNoCommandEnds() {
        var d = SpeechDetector()
        _ = run(&d, -65, ms: 500)
        d.open(heardSpeech: false, quietMs: 0, graceMs: 2000)
        XCTAssertEqual(run(&d, -65, ms: 2020), [.end], "end, not drop: the speech engine decides")
    }

    func testWakeTurnAfterAFastCommand() {
        var d = SpeechDetector()
        _ = run(&d, -65, ms: 500)
        // "hey jarvis, stop" said fast: the command ended 300 ms before the wake.
        d.open(heardSpeech: true, quietMs: 300, graceMs: 2000)
        XCTAssertEqual(run(&d, -65, ms: 260), [.end])
    }

    func testDbOfSamples() {
        XCTAssertEqual(SpeechDetector.db([Float](repeating: 0, count: 10)), -120)
        XCTAssertEqual(SpeechDetector.db([Float](repeating: 1, count: 10)), 0, accuracy: 0.001)
        XCTAssertEqual(SpeechDetector.db([Float](repeating: 0.1, count: 10)), -20, accuracy: 0.001)
    }
}

/// A fake trigger for the switch tests.
final class FakeTrigger: CancellableTrigger {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: ((String) -> Void)?
    var started = false
    func start() throws { started = true }
    func stop() { started = false }
}

/// A fake microphone: 16 kHz samples of one level, in blocks of 100 ms.
final class FakeSamples: SampleSource {
    var onSamples: (@Sendable ([Float]) -> Void)?
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws { self.onSamples = onSamples }
    func stop() { onSamples = nil }
    /// 0.0005 is about -66 dB (a quiet room). 0.05 is about -26 dB (speech).
    func emit(_ level: Float, ms: Int) {
        for _ in 0..<(ms / 100) { onSamples?([Float](repeating: level, count: 1600)) }
    }
}

/// A fake wake listener: it reports one hit after `hitAfterSamples`.
final class FakeListener: WakeListener, @unchecked Sendable {
    var hitAfterSamples: Int?
    var hit = WakeHit(phrase: "hey jarvis", prerollSeconds: 1.4, phraseEndSeconds: 0.4, voiceScore: 0.8, isOwner: true)
    var score: Double? = 0.8
    var voiceThreshold = 0.5
    private(set) var fed = 0
    private(set) var resets = 0
    func feed(_ samples: [Float]) -> WakeHit? {
        fed += samples.count
        if let n = hitAfterSamples, fed >= n {
            hitAfterSamples = nil
            return hit
        }
        return nil
    }
    func voiceScore(_ samples: [Float]) -> Double? { score }
    func reset() { resets += 1; fed = 0 }
    /// The near misses for the next `takeNearMisses()`.
    var misses: NearMisses?
    func takeNearMisses() -> NearMisses? { defer { misses = nil }; return misses }
}

// R-ON-4: the hold key stays as the fallback in always-on mode.
final class InputSwitchTests: XCTestCase {
    func testHoldOnlyByDefault() {
        let s = InputTriggers.make(EarshotSettings())
        XCTAssertEqual(s.mode, .hold)
        XCTAssertNil(s.alwaysOn)
    }

    func testAlwaysOnMakesBoth() {
        var settings = EarshotSettings()
        settings.mode = .alwaysOn
        let s = InputTriggers.make(settings, wake: FakeListener())
        XCTAssertEqual(s.mode, .alwaysOn)
        XCTAssertTrue(s.alwaysOn is WakeTrigger)
    }

    func testAlwaysOnWithoutModelsHasTheHoldKeyOnly() {
        var settings = EarshotSettings()
        settings.mode = .alwaysOn
        let s = InputTriggers.make(settings, wake: nil)
        XCTAssertNil(s.alwaysOn, "until the wake models load, the hold key works alone (R-ON-4)")
    }

    func testHoldKeyTakesOverFromAlwaysOn() {
        let hold = FakeTrigger(), always = FakeTrigger()
        let s = InputSwitch(hold: hold, alwaysOn: always)
        var log: [String] = []
        s.onStart = { log.append("start:\(s.current!.rawValue)") }
        s.onStop = { log.append("stop:\(s.current!.rawValue)") }
        s.onCancel = { _ in log.append("cancel:\(s.current!.rawValue)") }
        try? s.start()
        XCTAssertTrue(hold.started && always.started)

        always.onStart?()
        hold.onStart?()
        always.onStop?() // late, after the take-over: ignored
        hold.onStop?()
        XCTAssertEqual(log, ["start:alwaysOn", "cancel:alwaysOn", "start:hold", "stop:hold"])

        log.removeAll()
        always.onStart?()
        always.onCancel?("short")
        XCTAssertEqual(log, ["start:alwaysOn", "cancel:alwaysOn"])
    }
}

// R-ON-1, R-ON-3, D-11: the wake trigger.
final class WakeTriggerTests: XCTestCase {
    let quiet: Float = 0.0005
    let speech: Float = 0.05

    private func make(_ listener: FakeListener, config: WakeConfig = WakeConfig()) -> (WakeTrigger, FakeSamples, Recorder) {
        let source = FakeSamples()
        let trigger = WakeTrigger(listener: listener, config: config, source: source)
        let rec = Recorder()
        trigger.onWake = { _ in rec.add("wake") }
        trigger.onStart = { rec.add("start") }
        trigger.onStop = { rec.add("stop") }
        trigger.onCancel = { why in rec.add("cancel: \(why)") }
        trigger.onRejected = { _ in rec.add("rejected") }
        XCTAssertNoThrow(try trigger.start())
        return (trigger, source, rec)
    }

    func testWakePhraseOpensATurnThatEndsAfterTheCommand() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let stop = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)     // the phrase fires here; no words after it yet
        mic.emit(quiet, ms: 400)      // a short pause after the phrase does not end the turn
        mic.emit(speech, ms: 600)     // the command
        mic.emit(quiet, ms: 800)
        wait(for: [stop], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop"])
        t.stop()
    }

    func testOtherVoiceStartsNothing() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        listener.hit.isOwner = false
        listener.hit.voiceScore = 0.2
        let (t, mic, rec) = make(listener)
        let rejected = rec.expect("rejected", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 800)
        wait(for: [rejected], timeout: 2)
        XCTAssertEqual(rec.log, ["rejected"], "speech without the phrase never starts a turn")
        t.stop()
    }

    func testSpeechWithoutThePhraseStartsNothing() {
        let (t, mic, rec) = make(FakeListener())
        mic.emit(quiet, ms: 500)
        mic.emit(speech, ms: 1500)
        mic.emit(quiet, ms: 800)
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(rec.log, [])
        t.stop()
    }

    func testPhraseAloneEndsAfterTheGraceTime() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let stop = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(quiet, ms: 2200)     // no command: the turn ends after 2 s, and the text decides
        wait(for: [stop], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop"])
        t.stop()
    }

    func testFollowUpNeedsTheOwnersVoice() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let first = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 500)
        mic.emit(quiet, ms: 700)
        wait(for: [first], timeout: 2)

        // The owner's voice in the follow-up window: a turn with no phrase.
        t.openFollowUp()
        let second = rec.expect("stop", self, count: 2)
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 700)
        wait(for: [second], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop", "start", "stop"])

        // Another voice in the window: the turn starts, then the voice check drops it.
        listener.score = 0.2
        t.openFollowUp()
        let third = rec.expect("cancel: not the owner's voice (0.20)", self)
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 700)
        wait(for: [third], timeout: 2)
        XCTAssertTrue("not the owner's voice (0.20)".hasPrefix(WakeTrigger.otherVoice), "the app logs drops by this prefix")
        t.stop()
    }

    func testFollowUpWindowCloses() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let first = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 500)
        mic.emit(quiet, ms: 700)
        wait(for: [first], timeout: 2)
        t.openFollowUp()
        mic.emit(quiet, ms: 5200)     // the window is 5 s
        mic.emit(speech, ms: 600)
        mic.emit(quiet, ms: 700)
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop"])
        t.stop()
    }

    // D-11, live test 2026-11-02: the owner said the phrase again at the start of a follow-up turn.
    func testPhraseAgainInAFollowUpTurnMakesAWakeTurn() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let first = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 500)
        mic.emit(quiet, ms: 700)
        wait(for: [first], timeout: 2)

        var hits: [WakeHit] = []
        t.onWake = { hit in hits.append(hit); rec.add("wake") }
        listener.score = 0.2           // the voice of the whole turn would fail; the voice of the phrase counts
        listener.hitAfterSamples = 9600 // the spotter fires 0.6 s after the window opened
        t.openFollowUp()
        let second = rec.expect("stop", self, count: 2)
        mic.emit(speech, ms: 1000)
        mic.emit(quiet, ms: 700)
        wait(for: [second], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop", "start", "wake", "stop"], "no second start: the engine runs already")
        XCTAssertEqual(hits.count, 1)
        let after = hits.first?.inTurnAfterSeconds ?? -1
        XCTAssertGreaterThan(after, 0.3)
        XCTAssertLessThanOrEqual(after, 0.6, "the time from the start of the follow-up turn to the wake")
        t.stop()
    }

    func testPhraseLateInAFollowUpTurnIsNotHeard() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        var config = WakeConfig()
        config.followTurnWakeSeconds = 1.0
        let (t, mic, rec) = make(listener, config: config)
        let first = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 500)
        mic.emit(quiet, ms: 700)
        wait(for: [first], timeout: 2)

        listener.hitAfterSamples = 16000 * 2   // after the 1 s window: the spotter gets no audio then
        t.openFollowUp()
        let second = rec.expect("stop", self, count: 2)
        mic.emit(speech, ms: 3000)
        mic.emit(quiet, ms: 700)
        wait(for: [second], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop", "start", "stop"], "no wake: the phrase came after the window")
        t.stop()
    }

    func testOtherVoicePhraseInAFollowUpTurnKeepsTheVoiceCheck() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let first = rec.expect("stop", self)
        mic.emit(quiet, ms: 1000)
        mic.emit(speech, ms: 500)
        mic.emit(quiet, ms: 700)
        wait(for: [first], timeout: 2)

        listener.hit.isOwner = false
        listener.score = 0.2
        listener.hitAfterSamples = 9600
        t.openFollowUp()
        let dropped = rec.expect("cancel: not the owner's voice (0.20)", self)
        mic.emit(speech, ms: 1000)
        mic.emit(quiet, ms: 700)
        wait(for: [dropped], timeout: 2)
        XCTAssertEqual(rec.log, ["wake", "start", "stop", "start", "cancel: not the owner's voice (0.20)"])
        t.stop()
    }

    func testNearMissesAreReported() {
        let listener = FakeListener()
        var config = WakeConfig()
        config.nearMissReportSeconds = 1
        let (t, mic, rec) = make(listener, config: config)
        var got: [NearMisses] = []
        let reported = rec.expect("near misses", self)
        t.onNearMisses = { misses in got.append(misses); rec.add("near misses") }
        listener.misses = NearMisses(count: 2, best: 0.8)
        mic.emit(quiet, ms: 1200)
        wait(for: [reported], timeout: 2)
        XCTAssertEqual(got, [NearMisses(count: 2, best: 0.8)])
        t.stop()
    }

    func testPauseDropsTheOpenTurn() {
        let listener = FakeListener()
        listener.hitAfterSamples = 16000
        let (t, mic, rec) = make(listener)
        let start = rec.expect("start", self)
        mic.emit(quiet, ms: 1000)
        wait(for: [start], timeout: 2)
        let cancel = rec.expect("cancel: input stopped", self)
        t.setPaused(true)
        wait(for: [cancel], timeout: 2)
        t.stop()
    }
}

/// Collects the trigger events on the main thread.
final class Recorder: @unchecked Sendable {
    private(set) var log: [String] = []
    private var waits: [(String, Int, XCTestExpectation)] = []

    func add(_ event: String) {
        log.append(event)
        for (name, count, e) in waits where name == event && log.filter({ $0 == name }).count == count { e.fulfill() }
    }

    /// An expectation for the `count`th event of this name.
    func expect(_ event: String, _ test: XCTestCase, count: Int = 1) -> XCTestExpectation {
        let e = test.expectation(description: event)
        waits.append((event, count, e))
        return e
    }
}
