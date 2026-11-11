@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

// Item 10 of the gap list: a follow-up turn that is not a command shows no note and plays no sound. The log keeps it.

final class FollowUpQuietTests: XCTestCase {
    private func make(_ text: String) -> (CommandPipeline, TextEngine, NoteRecorder, Box) {
        let engine = TextEngine()
        engine.text = text
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: DryRunner(), names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { nil })
        let note = NoteRecorder()
        p.feedback = note
        let sounds = Box()
        p.playSound = { sounds.items.append($0) }
        p.wakePhrase = "hey atlas"
        return (p, engine, note, sounds)
    }

    final class Box { var items: [FeedbackSound] = [] }

    private let talk = "I think the blue fox was late again"

    func testFollowUpTalkIsQuietAndLogged() async {
        let (p, _, note, sounds) = make(talk)
        let r = await p.finish(mode: .alwaysOn)
        XCTAssertTrue(r.note.hasPrefix("not a command"), r.note)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.heard, talk, "the log keeps the record")
        XCTAssertTrue(note.shown.isEmpty, "\(note.shown)")
        XCTAssertEqual(sounds.items, [])
        XCTAssertNil(p.lastSound, "no sound, so nothing to mute")
        XCTAssertTrue(p.followUpMissed, "the follow-up window does not open again")
    }

    func testWakeTurnStillGetsTheNoteAndTheSound() async {
        let (p, _, note, sounds) = make(talk)
        p.pendingWake = WakeHit(phrase: "hey atlas", prerollSeconds: 1.2, voiceScore: 0.6, isOwner: true)
        let r = await p.finish(mode: .alwaysOn)
        XCTAssertTrue(r.note.hasPrefix("not a command"), r.note)
        XCTAssertEqual(note.shown.count, 1)
        XCTAssertEqual(sounds.items, [.failed])
        XCTAssertFalse(p.followUpMissed)
    }

    func testHoldKeyTurnStillGetsTheNoteAndTheSound() async {
        let (p, _, note, sounds) = make(talk)
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(note.shown.count, 1)
        XCTAssertEqual(sounds.items, [.failed])
        XCTAssertFalse(p.followUpMissed)
    }

    func testFlagClearsOnTheNextTurn() async {
        let (p, e, _, _) = make(talk)
        _ = await p.finish(mode: .alwaysOn)
        XCTAssertTrue(p.followUpMissed)
        e.text = "open notes"
        let r = await p.finish(mode: .alwaysOn)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertFalse(p.followUpMissed)
    }

    func testRule() {
        let wake = WakeHit(phrase: "hey atlas", prerollSeconds: 1, voiceScore: 0.6, isOwner: true)
        XCTAssertTrue(CommandPipeline.isFollowUpMiss(mode: .alwaysOn, wake: nil, commandWord: false))
        XCTAssertFalse(CommandPipeline.isFollowUpMiss(mode: .alwaysOn, wake: wake, commandWord: false))
        XCTAssertFalse(CommandPipeline.isFollowUpMiss(mode: .alwaysOn, wake: nil, commandWord: true))
        XCTAssertFalse(CommandPipeline.isFollowUpMiss(mode: .hold, wake: nil, commandWord: false))
    }
}
