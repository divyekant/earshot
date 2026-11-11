import Foundation
import XCTest
@testable import PACore

/// Phase 2, Q4: the project focus, the project proposals and the duplicate notice (build spec 8.1 to 8.3).
/// The tests use the hash model. All words are made-up.
final class ProposalTests: XCTestCase {
    func engine(model: Bool = true) -> (Engine, MemoryOutput, FixedClock) {
        let clock = FixedClock(wed(10))
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: clock, output: out, textReader: FileTextReader())
        if model {
            let host = ModelHost(modelID: "hash-256-v1") { HashEmbedder() }
            host.rules = ModelRules(projectA: 0.05, projectB: 0, duplicateC: 0.95)
            e.models = host
        }
        e.start()
        return (e, out, clock)
    }

    /// Sends a command. Gives the answer and the notes with no `re` that came after it.
    @discardableResult
    func say(_ e: Engine, _ out: MemoryOutput, _ lead: String, _ text: String = "") -> (answer: String, later: [String]) {
        e.handle(.command(id: UUID().uuidString, lead: lead, text: text, context: [:]))
        var answer = ""
        var later: [String] = []
        for m in out.take() {
            guard case .answer(let re, _, let t, _) = m else { continue }
            if re != nil { answer = t } else { later.append(t) }
        }
        return (answer, later)
    }

    func testFocusSendsCapturesToTheNewProject() {
        let (e, out, clock) = engine(model: false)
        XCTAssertEqual(say(e, out, "new project", "kitchen").answer, "Project · Kitchen · your next captures go here for 5 minutes")
        XCTAssertEqual(say(e, out, "todo", "buy the tile glue").answer, "To-do · Kitchen · buy the tile glue")
        XCTAssertEqual(e.store!.openItems().last!.projectBy, "owner")
        // Each capture starts the 5 minutes again.
        clock.now = clock.now.addingTimeInterval(4 * 60)
        XCTAssertEqual(say(e, out, "note", "grout colour is grey").answer, "Note · Kitchen · grout colour is grey")
        clock.now = clock.now.addingTimeInterval(4 * 60)
        XCTAssertEqual(say(e, out, "todo", "call the tiler").answer, "To-do · Kitchen · call the tiler")
        clock.now = clock.now.addingTimeInterval(6 * 60)
        XCTAssertEqual(say(e, out, "todo", "renew the passport").answer, "To-do · renew the passport")
    }

    func testFocusEndsWithAnotherProjectOrNoProject() {
        let (e, out, _) = engine(model: false)
        say(e, out, "new project", "kitchen")
        say(e, out, "new project", "garden")
        XCTAssertEqual(say(e, out, "todo", "buy seeds").answer, "To-do · Garden · buy seeds")
        XCTAssertEqual(say(e, out, "move", "it to no project").answer, "Moved · no project · buy seeds")
        XCTAssertEqual(say(e, out, "todo", "book the dentist").answer, "To-do · book the dentist")
    }

    func testFocusCanBeOff() {
        let (e, out, _) = engine(model: false)
        e.settings.projectFocusMinutes = 0
        XCTAssertEqual(say(e, out, "new project", "kitchen").answer, "Project · Kitchen")
        XCTAssertEqual(say(e, out, "todo", "buy the tile glue").answer, "To-do · buy the tile glue")
    }

    func testDuplicateNotice() {
        let (e, out, clock) = engine()
        say(e, out, "todo", "order the green paint")
        clock.now = clock.now.addingTimeInterval(120)
        let r = say(e, out, "todo", "order the green paint")
        XCTAssertEqual(r.answer, "To-do · order the green paint")
        XCTAssertEqual(r.later, ["To-do · like one that you have: order the green paint"])
        // Both are kept. No merge, no drop.
        XCTAssertEqual(e.store!.openItems().count, 2)
        // A different thing: no notice.
        XCTAssertEqual(say(e, out, "todo", "book the dentist").later, [])
        // A note is not compared.
        XCTAssertEqual(say(e, out, "note", "order the green paint").later, [])
    }

    func testProposalsCanBeOff() {
        let (e, out, _) = engine()
        e.settings.projectFocusMinutes = 0
        XCTAssertTrue(e.settings.proposeProject)
        e.settings.proposeProject = false
        say(e, out, "new project", "kitchen")
        for t in ["kitchen tiles floor", "kitchen tiles wall", "kitchen tiles grout"] { say(e, out, "todo", t + " for kitchen") }
        let r = say(e, out, "todo", "kitchen tiles order")
        XCTAssertEqual(r.later, [])
        XCTAssertNil(e.store!.openItems().last!.projectID)
    }

    func testProposalSetsTheProjectWithAQuestionMark() throws {
        let (e, out, clock) = engine()
        e.settings.projectFocusMinutes = 0
        e.settings.proposeProject = true
        say(e, out, "new project", "kitchen")
        say(e, out, "new project", "garden")
        for t in ["tiles floor", "tiles wall", "tiles grout"] { say(e, out, "todo", "kitchen " + t + " for kitchen") }
        for t in ["seeds", "hose", "spade"] { say(e, out, "todo", "garden " + t + " for garden") }
        let r = say(e, out, "todo", "kitchen tiles order")
        XCTAssertEqual(r.answer, "To-do · kitchen tiles order")
        XCTAssertEqual(r.later, ["To-do · Kitchen? · kitchen tiles order"])
        let it = e.store!.openItems().last!
        XCTAssertEqual(it.projectBy, "search")
        XCTAssertEqual(e.projectName(it.projectID), "Kitchen")
        e.flushPages(force: true)
        let page = try String(contentsOf: e.pagesFolder.appendingPathComponent("all-open.html"), encoding: .utf8)
        XCTAssertTrue(page.contains("kitchen tiles order"))
        // The owner corrects it in 10 minutes or less: a wrong proposal.
        clock.now = clock.now.addingTimeInterval(60)
        XCTAssertEqual(say(e, out, "move", "it to garden").answer, "Moved · Garden · kitchen tiles order")
        XCTAssertEqual(e.store!.eventCounts(since: wed(0))["proposal-corrected"], 1)
        XCTAssertEqual(e.store!.item(it.id)!.projectBy, "owner")
    }

    /// Project rule version 2: a project with fewer than 3 owner records gets no proposal, even if its name is in
    /// the capture. A proposal does not count as an owner record.
    func testNoProposalForAProjectWithFewRecords() {
        let (e, out, _) = engine()
        e.settings.projectFocusMinutes = 0
        say(e, out, "new project", "garden")
        for t in ["seeds", "hose"] { say(e, out, "todo", "garden " + t + " for garden") }
        let r = say(e, out, "todo", "garden spade")
        XCTAssertEqual(r.later, [])
        XCTAssertNil(e.store!.openItems().last!.projectID)
    }

    /// Without the name: the 5 nearest records and the first 3 keyword results must agree.
    func testProposalFromNeighborsAndKeywords() {
        var rule = ProjectRuleV2()
        rule.minRecords = 3
        func rec(_ p: String, _ t: String, _ v: [Float]) -> ProjectRuleV2.Record { .init(project: p, vector: v, text: t) }
        let a: [Float] = [1, 0], b: [Float] = [0, 1]
        let records = [rec("1", "tile glue and grout", a), rec("1", "grout colour grey", a), rec("1", "grout float", a),
                       rec("1", "tile spacers", a), rec("1", "tile cutter hire", a),
                       rec("2", "seeds", b), rec("2", "hose", b), rec("2", "spade", b)]
        let projects = [(id: "1", name: "Kitchen"), (id: "2", name: "Garden")]
        XCTAssertEqual(rule.propose(title: "buy more grout", vector: a, records: records, projects: projects, floor: 0)?.project, "1")
        // The neighbors agree, but no keyword result: no proposal.
        XCTAssertNil(rule.propose(title: "call the fitter", vector: a, records: records, projects: projects, floor: 0))
        // Below the floor: no neighbor counts.
        XCTAssertNil(rule.propose(title: "buy more grout", vector: [0.1, 0], records: records, projects: projects, floor: 0.5))
    }

    func testAMoveToTheSameProjectConfirms() {
        let (e, out, clock) = engine()
        e.settings.projectFocusMinutes = 0
        e.settings.proposeProject = true
        say(e, out, "new project", "kitchen")
        say(e, out, "new project", "garden")
        for t in ["tiles floor", "tiles wall", "tiles grout"] { say(e, out, "todo", "kitchen " + t + " for kitchen") }
        for t in ["seeds", "hose", "spade"] { say(e, out, "todo", "garden " + t + " for garden") }
        say(e, out, "todo", "kitchen tiles order")
        clock.now = clock.now.addingTimeInterval(60)
        say(e, out, "move", "it to kitchen")
        XCTAssertNil(e.store!.eventCounts(since: wed(0))["proposal-corrected"])
        XCTAssertEqual(e.store!.openItems().last!.projectBy, "owner")
    }

    func testCaptureAnswerDoesNotWaitForTheModel() {
        // A model that does not load: the capture is saved and answered, with no second note.
        struct Broken: Error {}
        let out = MemoryOutput()
        let e = Engine(folder: tempFolder(), clock: FixedClock(wed(10)), output: out)
        let host = ModelHost(modelID: "broken") { throw Broken() }
        host.rules = ModelRules(projectA: 0, projectB: 0, duplicateC: 0)
        e.models = host
        e.start()
        let r = say(e, out, "todo", "order the green paint")
        XCTAssertEqual(r.answer, "To-do · order the green paint")
        XCTAssertEqual(r.later, [])
    }
}
