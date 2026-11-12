import Foundation
import XCTest
@testable import PACore

/// Phase 3, package S2: settings, store tables, the fixture sources, the time limit, and the flag commands.
/// Made-up data only.
final class Phase3FrameTests: XCTestCase {
    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "") -> Outgoing {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
        return out.take().last!
    }

    func mailFixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/phase3/mail")!
    }

    // MARK: - Settings (spec 7.2)

    func testSettingsDefaults() throws {
        let s = PASettings()
        XCTAssertEqual(s.sources, SourceSwitches())
        XCTAssertTrue(s.sources.calendar && s.sources.mail && s.sources.notes)
        XCTAssertEqual(s.nearEventMinutes, 15)
        XCTAssertEqual(s.mail.everyMinutes, 5)
        XCTAssertEqual(s.mail.firstDays, 3)
        XCTAssertEqual(s.mail.maxPerRead, 50)
        XCTAssertEqual(s.mail.batch, 10)
        XCTAssertEqual(s.notes.everyMinutes, 15)
        // Off: the request flags failed their go mark on the sealed holdout (E11).
        XCTAssertEqual(s.rules.request, .off)
        XCTAssertTrue(s.flagsLearn)
        XCTAssertEqual(s.owner, OwnerSettings())
    }

    func testSettingsPartialFile() throws {
        let json = #"{"sources": {"mail": false}, "mail": {"batch": 5}, "rules": {"request": "off"},"#
            + #" "projects": {"kitchen": {"request": "alert"}}, "owner": {"addresses": ["maya.rao@example.com"]}}"#
        let s = try JSONDecoder().decode(PASettings.self, from: Data(json.utf8))
        XCTAssertFalse(s.sources.mail)
        XCTAssertTrue(s.sources.calendar)
        XCTAssertEqual(s.mail.batch, 5)
        XCTAssertEqual(s.mail.everyMinutes, 5)
        XCTAssertEqual(s.rules.request, .off)
        XCTAssertEqual(s.rules(project: "Kitchen").request, .alert)
        XCTAssertEqual(s.owner.addresses, ["maya.rao@example.com"])
        XCTAssertEqual(s.owner.names, [])
    }

    // MARK: - Store (spec 7.3)

    func testMigrationFromVersion2() throws {
        let folder = tempFolder()
        let url = folder.appendingPathComponent("pa.sqlite")
        do {
            let store = try Store(url: url)
            try store.db.exec("DROP TABLE cal_event; DROP TABLE cal_event_link; DROP TABLE flag; DROP TABLE source_seen; PRAGMA user_version = 2;")
        }
        let store = try Store(url: url)
        XCTAssertEqual(try store.db.query("PRAGMA user_version").first?.first?.int, 3)
        for t in ["cal_event", "cal_event_link", "flag", "source_seen"] {
            XCTAssertEqual(try store.db.query("SELECT count(*) FROM \(t)").first?.first?.int, 0, t)
        }
    }

    func testOneOpenFlagForEachConversation() throws {
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        var f = Flag(kind: .request, source: .mail, sourceID: "1", sender: "Sam Lee", subject: "Signed form",
                     sentence: "Could you send me the signed form?", sourceAt: wed(9), createdAt: wed(10))
        let a = try store.upsertFlag(f)
        f.sourceID = "2"
        f.subject = "Re: Signed form"
        f.sentence = "Could you send it before Friday?"
        let b = try store.upsertFlag(f)
        XCTAssertEqual(a, b)
        XCTAssertEqual(store.openFlags().count, 1)
        XCTAssertEqual(store.openFlags().first?.sentence, "Could you send it before Friday?")
        // Another sender: a new flag.
        f.sender = "Priya Shah"
        XCTAssertNotEqual(try store.upsertFlag(f), a)
        XCTAssertEqual(store.openFlags().count, 2)
    }

    func testMailLink() {
        var f = Flag(kind: .request, source: .mail, sourceID: "1", sender: "", subject: "", sentence: "",
                     sourceAt: wed(9), createdAt: wed(9))
        f.messageID = "<abc.123@mail.example.org>"
        XCTAssertEqual(f.mailLink, "message://%3Cabc.123@mail.example.org%3E")
        f.source = .note
        XCTAssertNil(f.mailLink)
    }

    func testSeenRetriesThenFailed() throws {
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        try store.markSeen(.mail, "77", .retry, at: wed(10))
        try store.markSeen(.mail, "77", .retry, at: wed(10))
        XCTAssertEqual(store.seen(.mail, "77")?.result, .retry)
        try store.markSeen(.mail, "77", .retry, at: wed(10))
        XCTAssertEqual(store.seen(.mail, "77")?.result, .failed)
        try store.markSeen(.mail, "78", .bulk, at: wed(10))
        XCTAssertEqual(store.seen(.mail, "78")?.result, .bulk)
    }

    func testForgetSource() throws {
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        let f = Flag(kind: .request, source: .mail, sourceID: "1", sender: "Sam Lee", subject: "Form",
                     sentence: "Could you sign it?", sourceAt: wed(9), createdAt: wed(10))
        try store.upsertFlag(f)
        try store.markSeen(.mail, "1", .flag, at: wed(10))
        let e = CalEvent(sourceID: "ev1", title: "Dentist", startsAt: wed(15), endsAt: wed(16))
        let eid = try store.upsertEvent(e)
        try store.addEventLink(EventLink(eventID: eid, itemID: 1, by: "owner"), at: wed(10))
        try store.forgetSource(.mail)
        XCTAssertEqual(store.openFlags().count, 0)
        XCTAssertNil(store.seen(.mail, "1"))
        XCTAssertEqual(store.events(from: wed(0), to: wed(23)).count, 1)
        try store.forgetSource(.calendar)
        XCTAssertEqual(store.events(from: wed(0), to: wed(23)).count, 0)
        XCTAssertEqual(store.eventLinks(eid).count, 0)
    }

    func testEventsUpsertAndPrune() throws {
        let store = try Store(url: tempFolder().appendingPathComponent("pa.sqlite"))
        var e = CalEvent(sourceID: "ev1", title: "Dentist", startsAt: wed(15), endsAt: wed(16), people: ["Dr Lee"])
        let a = try store.upsertEvent(e)
        e.title = "Dentist check"
        XCTAssertEqual(try store.upsertEvent(e), a)
        XCTAssertEqual(store.events(from: wed(0), to: wed(23)).first?.title, "Dentist check")
        XCTAssertEqual(store.events(from: wed(0), to: wed(23)).first?.people, ["Dr Lee"])
        try store.upsertEvent(CalEvent(sourceID: "ev2", title: "Lunch", startsAt: wed(12), endsAt: wed(13)))
        // ev2 is not in the source any more.
        try store.pruneEvents(now: wed(10), keep: ["ev1"], readFrom: wed(0))
        XCTAssertEqual(store.events(from: wed(0), to: wed(23)).map(\.sourceID), ["ev1"])
        // 1 day after the end, the event goes.
        try store.pruneEvents(now: wed(17).addingTimeInterval(86400 + 60))
        XCTAssertEqual(store.events(from: wed(0), to: wed(23)).count, 0)
    }

    func testFlagExamplesKeepNoText() throws {
        let index = try IndexStore(url: tempFolder().appendingPathComponent("index.sqlite"))
        try index.addFlagExample(flag: 3, features: [1, 0, 0.5], vector: nil, answer: "kept", at: wed(10))
        let ex = index.flagExamples()
        XCTAssertEqual(ex.count, 1)
        XCTAssertEqual(ex[0].features, [1, 0, 0.5])
        XCTAssertEqual(ex[0].answer, "kept")
    }

    // MARK: - Fixture sources and the time limit (spec 7.4)

    func testFixtureMailReadsTrainAndDev() throws {
        let train = try FixtureMail(jsonl: mailFixture("train"))
        XCTAssertEqual(train.messages.count, 400)
        let dev = try FixtureMail(jsonl: mailFixture("dev"))
        XCTAssertEqual(dev.messages.count, 200)
        // Newest first.
        XCTAssertTrue(zip(dev.messages, dev.messages.dropFirst()).allSatisfy { $0.date >= $1.date })
        let ids = try dev.ids(from: 0, count: 10)
        XCTAssertEqual(ids.count, 10)
        let env = try dev.envelope(id: ids[0])
        XCTAssertEqual(env.text, "")
        XCTAssertFalse(try dev.text(id: ids[0]).isEmpty)
        let notes = try FixtureNotes(jsonl: mailFixture("notes-dev"))
        XCTAssertEqual(try notes.notes().count, 30)
    }

    func testSourceReaderTimeLimit() {
        let reader = SourceReader(name: "test", limit: 0.2)
        let gate = DispatchSemaphore(value: 0)
        if case .timedOut = reader.run({ gate.wait(); return 1 }) {} else { XCTFail("no time limit") }
        // The old batch still runs: a new batch waits for the next time.
        if case .busy = reader.run({ 2 }) {} else { XCTFail("not busy") }
        gate.signal()
        Thread.sleep(forTimeInterval: 0.1)
        if case .done(let v) = reader.run({ 3 }) { XCTAssertEqual(v, 3) } else { XCTFail("no result") }
        if case .failed = reader.run({ throw SourceError("x") }) {} else { XCTFail("no error") }
    }

    // MARK: - Commands (spec 7.1 and 8.6)

    func testKeepWithWordsSavesANote() {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "keep", "the tile shop closes at 6").text,
                       "Saved as a note. To keep a flag, say its number.")
        XCTAssertEqual(e.store?.items(where: "kind = 'note'").count, 1)
        XCTAssertEqual(say(e, out, "keep", "2").text, "No flag 2 in the last list. Say \"what is new\".")
    }

    func addFlag(_ e: Engine, sender: String, subject: String, sentence: String, due: Day? = nil, at: Date) {
        var f = Flag(kind: .request, source: .mail, sourceID: UUID().uuidString, sender: sender, subject: subject,
                     sentence: sentence, sourceAt: at, createdAt: at)
        f.messageID = "<\(f.sourceID)@mail.example.org>"
        f.dueOn = due
        try! e.store!.upsertFlag(f)
    }

    func testWhatIsNewKeepAndDrop() throws {
        let (e, out, _) = makeEngine()
        XCTAssertEqual(say(e, out, "what is new").text, "Nothing new.")
        say(e, out, "new project", "kitchen")
        addFlag(e, sender: "Sam Lee", subject: "Signed form", sentence: "Could you send me the signed form before the 20th?",
                due: Day(2026, 11, 20), at: wed(8))
        addFlag(e, sender: "Kowalski Plumbing", subject: "Deposit", sentence: "Please pay the deposit before 30 November.",
                at: wed(9))
        addFlag(e, sender: "Priya Shah", subject: "Dinner", sentence: "Which date works better for you?", at: wed(7))
        let list = say(e, out, "what new")
        XCTAssertEqual(list.text, "New")
        XCTAssertEqual(list.items, ["Request · Kowalski Plumbing · Please pay the deposit before 30 November.",
                                    "Request · Sam Lee · Could you send me the signed form before the 20th? · 20 Nov?",
                                    "Request · Priya Shah · Which date works better for you?"])
        // keep 2: a to-do with the sentence and the proposed day, and a link to the mail.
        let kept = say(e, out, "keep", "2 for kitchen")
        XCTAssertTrue(kept.text.hasPrefix("To-do"), kept.text)
        XCTAssertTrue(kept.text.contains("Kitchen"), kept.text)
        XCTAssertTrue(kept.text.contains("Could you send me the signed form before the 20th?"), kept.text)
        let todo = try XCTUnwrap(e.store?.items(where: "kind = 'todo'").first)
        XCTAssertEqual(todo.dueOn, Day(2026, 11, 20))
        let doc = try XCTUnwrap(todo.docID.flatMap { e.store?.doc($0) })
        XCTAssertTrue(doc.address?.hasPrefix("message://%3C") ?? false)
        XCTAssertEqual(say(e, out, "keep", "2").text, "Flag 2 is kept already.")
        // keep with the owner's words as the title.
        say(e, out, "what is new")
        XCTAssertTrue(say(e, out, "keep", "2 as call Priya about the dinner").text.hasSuffix("call Priya about the dinner"))
        // drop 1, and "done" on a flag.
        say(e, out, "what is new")
        XCTAssertEqual(say(e, out, "done", "1").text, Engine.flagOnly)
        XCTAssertEqual(say(e, out, "drop", "1").text, "Dropped · Please pay the deposit before 30 November.")
        XCTAssertEqual(say(e, out, "what is new").text, "Nothing new.")
        XCTAssertEqual(e.store?.flagAnswers(since: wed(0)), ["kept": 2, "dropped": 1])
    }

    func testSourceOffForgetsItsData() throws {
        let (e, _, _) = makeEngine()
        addFlag(e, sender: "Sam Lee", subject: "Form", sentence: "Could you sign it?", at: wed(9))
        var s = e.settings
        let old = s
        s.sources.mail = false
        e.settings = s
        e.settingsChanged(from: old)
        XCTAssertEqual(e.store?.openFlags().count, 0)
    }

    func testLeadsMatchManifest() {
        XCTAssertEqual(PACommand.from(lead: "keep"), .keep)
        XCTAssertEqual(PACommand.from(lead: "keep this"), .keepThis)
        XCTAssertEqual(PACommand.from(lead: "what new"), .whatIsNew)
        XCTAssertEqual(PACommand.from(lead: "What is new"), .whatIsNew)
    }
}
