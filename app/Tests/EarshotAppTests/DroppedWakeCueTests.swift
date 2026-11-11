import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotInput
import EarshotRouter
import XCTest

// Gap item 7: a wake turn that got the start sound and then failed the voice check of the turn gets a short cue.
// Its words stay in memory for a short time, and one hold-key press with no words types them.

final class DroppedWakeCueTests: XCTestCase {
    final class Sounds { var items: [FeedbackSound] = [] }

    private let wake = WakeHit(phrase: "hey atlas", prerollSeconds: 1.2, voiceScore: 0.4, isOwner: true)

    private func make() -> (CommandPipeline, TextEngine, FieldRunner, NoteRecorder, Sounds) {
        let engine = TextEngine()
        let runner = FieldRunner()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names },
                                frontBundleID: { "com.anthropic.claudefordesktop" })
        p.wakePhrase = "hey atlas"
        let note = NoteRecorder()
        p.feedback = note
        let sounds = Sounds()
        p.playSound = { sounds.items.append($0) }
        return (p, engine, runner, note, sounds)
    }

    func testOnlyAWakeTurnDroppedForTheVoiceGetsTheCue() {
        XCTAssertTrue(CommandPipeline.cuesDrop("not the owner's voice (0.22)", wake: wake))
        XCTAssertFalse(CommandPipeline.cuesDrop("not the owner's voice (0.22)", wake: nil), "a follow-up turn had no start sound")
        XCTAssertFalse(CommandPipeline.cuesDrop("follow-up too short for a voice check (0.40 s)", wake: nil))
        XCTAssertFalse(CommandPipeline.cuesDrop("the hold key took over", wake: wake))
        XCTAssertTrue(WakeTrigger.otherVoice.hasPrefix("not the owner's voice"))
    }

    func testDropPlaysTheCueAndKeepsTheWordsWithoutThePhrase() async {
        let (p, engine, runner, note, sounds) = make()
        engine.text = "Hey Atlas, the blue fox is late"
        await p.dropWakeTurn(wake)
        XCTAssertEqual(sounds.items, [.notMatched])
        XCTAssertEqual(note.shown.count, 1)
        XCTAssertTrue(note.shown.first?.0.contains("did not match") == true, "\(note.shown)")
        let kept = p.keptText?.text.lowercased() ?? ""
        XCTAssertTrue(kept.contains("blue fox is late"), kept)
        XCTAssertFalse(kept.contains("atlas"), kept)
        XCTAssertTrue(runner.runs.isEmpty, "nothing runs at the drop")
    }

    func testHoldKeyPressWithNoWordsTypesTheKeptWords() async {
        let (p, engine, runner, _, _) = make()
        engine.text = "Hey Atlas, the blue fox is late"
        await p.dropWakeTurn(wake)
        engine.text = ""
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        guard case .typeText(let typed)? = runner.runs.first?.0 else { return XCTFail("\(runner.runs)") }
        XCTAssertTrue(typed.lowercased().contains("blue fox is late"), typed)
        XCTAssertEqual(runner.runs.first?.1.mode, .hold)
        XCTAssertEqual(r.heard, "(5 words)", "the log keeps the word count, not the words")
        XCTAssertFalse(r.note.contains("blue"), r.note)
        XCTAssertNil(p.keptText, "one use")
    }

    func testKeptWordsNeverSend() async {
        let (p, engine, runner, _, _) = make()
        engine.text = "Hey Atlas, the blue fox is late and send"
        await p.dropWakeTurn(wake)
        engine.text = ""
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.count, 1, "\(runner.runs)")
        XCTAssertFalse(runner.runs.contains { $0.0 == .send })
        XCTAssertTrue(r.note.contains("not sent"), r.note)
    }

    func testKeptWordsExpire() async {
        let (p, engine, runner, _, _) = make()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        p.now = { clock }
        engine.text = "Hey Atlas, the blue fox is late"
        await p.dropWakeTurn(wake)
        clock = clock.addingTimeInterval(CommandPipeline.keptSeconds + 1)
        engine.text = ""
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(runner.runs.isEmpty)
        XCTAssertEqual(r.note, "no words")
    }

    func testAnyOtherTurnDropsTheKeptWords() async {
        let (p, engine, runner, _, _) = make()
        engine.text = "Hey Atlas, the blue fox is late"
        await p.dropWakeTurn(wake)
        engine.text = "open notes"
        _ = await p.finish(mode: .hold)
        engine.text = ""
        runner.runs = []
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(runner.runs.isEmpty, "the kept words are for the next turn only")
    }

    func testAlwaysOnTurnWithNoWordsDoesNotType() async {
        let (p, engine, runner, _, _) = make()
        engine.text = "Hey Atlas, the blue fox is late"
        await p.dropWakeTurn(wake)
        engine.text = ""
        _ = await p.finish(mode: .alwaysOn)
        XCTAssertTrue(runner.runs.isEmpty, "only the hold key types the kept words")
    }

    func testNoCueSoundWhenSoundsAreOff() async {
        let (p, engine, _, note, sounds) = make()
        p.playSounds = false
        p.showFeedback = false
        engine.text = "Hey Atlas, open notes"
        await p.dropWakeTurn(wake)
        XCTAssertEqual(sounds.items, [])
        XCTAssertTrue(note.shown.isEmpty)
    }
}
