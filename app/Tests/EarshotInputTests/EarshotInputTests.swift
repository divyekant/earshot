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

    func testDbOfSamples() {
        XCTAssertEqual(SpeechDetector.db([Float](repeating: 0, count: 10)), -120)
        XCTAssertEqual(SpeechDetector.db([Float](repeating: 1, count: 10)), 0, accuracy: 0.001)
        XCTAssertEqual(SpeechDetector.db([Float](repeating: 0.1, count: 10)), -20, accuracy: 0.001)
    }
}

// R-ON-2, R-ON-5: the "for me?" gate.
final class ForMeGateTests: XCTestCase {
    let gate = ForMeGate()
    let apps = [
        AppEntry(id: "a1", name: "Slack", bundleID: "x.slack", aliases: ["slack"], isChat: true, approved: true),
        AppEntry(id: "a2", name: "Messages", bundleID: "x.msg", aliases: ["imessage", "text"], isChat: true, approved: true),
        AppEntry(id: "a3", name: "Notion", bundleID: "x.notion", approved: false),
    ]

    func testPrefixPasses() {
        XCTAssertTrue(gate.check("Slack Ravi, running late", apps: apps, secondsSinceLastCommand: nil).isForMe)
        XCTAssertTrue(gate.check("click the second result", apps: apps, secondsSinceLastCommand: nil).isForMe)
        XCTAssertTrue(gate.check("iMessage mom", apps: apps, secondsSinceLastCommand: nil).isForMe)
    }

    func testTalkToPeopleIsRejected() {
        XCTAssertFalse(gate.check("I think we should get lunch", apps: apps, secondsSinceLastCommand: nil).isForMe)
        XCTAssertFalse(gate.check("", apps: apps, secondsSinceLastCommand: nil).isForMe)
    }

    func testUnapprovedAppDoesNotCount() {
        XCTAssertFalse(gate.check("Notion is slow today", apps: apps, secondsSinceLastCommand: nil).isForMe)
    }

    func testFollowUpWindow() {
        XCTAssertTrue(gate.check("running late", apps: apps, secondsSinceLastCommand: 2).isForMe)
        XCTAssertFalse(gate.check("running late", apps: apps, secondsSinceLastCommand: 9).isForMe)
        XCTAssertFalse(gate.check("running late", apps: apps, secondsSinceLastCommand: 2, inCall: true).isForMe)
    }

    func testSendNeedsShortCommandInWindow() {
        XCTAssertEqual(gate.check("send", apps: apps, secondsSinceLastCommand: 2),
                       .forMe(text: "send", maySend: true, why: "send in the follow-up window"))
        XCTAssertFalse(gate.check("send", apps: apps, secondsSinceLastCommand: nil).isForMe, "no command before it")
        XCTAssertFalse(gate.check("send", apps: apps, secondsSinceLastCommand: 2, inCall: true).isForMe, "in a call")
        XCTAssertFalse(gate.check("did you send the report", apps: apps, secondsSinceLastCommand: 2).isForMe)
    }

    func testSendInsideCommandNeverMaySend() {
        guard case .forMe(_, let maySend, _) = gate.check("Slack Ravi I will send it later", apps: apps, secondsSinceLastCommand: nil)
        else { return XCTFail() }
        XCTAssertFalse(maySend)
    }

    func testLongTalkInWindowNeedsPrefix() {
        let long = Array(repeating: "word", count: 40).joined(separator: " ")
        XCTAssertFalse(gate.check(long, apps: apps, secondsSinceLastCommand: 1).isForMe)
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

final class FakeLevels: LevelSource {
    var onLevel: (@Sendable (Double) -> Void)?
    func start(frameMs: Double, onLevel: @escaping @Sendable (Double) -> Void) throws { self.onLevel = onLevel }
    func stop() { onLevel = nil }
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
        let s = InputTriggers.make(settings)
        XCTAssertEqual(s.mode, .alwaysOn)
        XCTAssertNotNil(s.alwaysOn)
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

    func testAlwaysOnTriggerReportsTurn() {
        let levels = FakeLevels()
        let t = AlwaysOnTrigger(source: levels)
        var log: [String] = []
        let done = expectation(description: "turn")
        t.onStart = { log.append("start") }
        t.onStop = { log.append("stop"); done.fulfill() }
        t.onCancel = { _ in log.append("cancel") }
        XCTAssertNoThrow(try t.start())
        for _ in 0..<50 { levels.onLevel?(-65) }
        for _ in 0..<30 { levels.onLevel?(-25) }
        for _ in 0..<40 { levels.onLevel?(-65) }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(log, ["start", "stop"])
        t.stop()
    }
}
