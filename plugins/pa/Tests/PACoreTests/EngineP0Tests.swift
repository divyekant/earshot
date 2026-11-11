import Foundation
import XCTest
@testable import PACore

final class EngineP0Tests: XCTestCase {
    func testSettingsFileHasTheDefaults() throws {
        let (e, _, _) = makeEngine()
        let data = try Data(contentsOf: e.settingsURL)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["morningTime"] as? String, "09:00")
        XCTAssertEqual((obj["rules"] as? [String: Any])?["time"] as? String, "alert")
        XCTAssertEqual((obj["reminders"] as? [String: Any])?["list"] as? String, "earshot")
    }

    func testBadSettingsFileUsesTheDefaults() throws {
        let folder = tempFolder()
        try Data("{ not json".utf8).write(to: folder.appendingPathComponent("settings.json"))
        let out = MemoryOutput()
        let e = Engine(folder: folder, clock: FixedClock(wed(10)), output: out)
        e.start()
        XCTAssertEqual(e.settings, PASettings())
        XCTAssertEqual(out.take().map(\.text), [PASettings.errorNote])
    }

    func testUnknownKeyAndPartialFile() throws {
        let folder = tempFolder()
        try Data(#"{"morningTime":"08:30","colour":"blue","rules":{"due":"alert"}}"#.utf8).write(to: folder.appendingPathComponent("settings.json"))
        let e = Engine(folder: folder, clock: FixedClock(wed(10)), output: MemoryOutput())
        e.start()
        XCTAssertEqual(e.settings.morningTime, ClockTime(8, 30))
        XCTAssertEqual(e.settings.rules.due, .alert)
        XCTAssertEqual(e.settings.rules.time, .alert)
        XCTAssertEqual(e.settings.rules(project: "Kitchen").due, .alert)
    }

    func testEachCommandHasOneAnswerWithRe() {
        let (e, out, _) = makeEngine()
        for (n, lead) in PACommand.leads.keys.sorted().enumerated() {
            e.handle(.command(id: "c\(n)", lead: lead, text: "x", context: [:]))
        }
        let answers = out.take()
        XCTAssertEqual(answers.count, PACommand.leads.count)
        XCTAssertEqual(Set(answers.compactMap(\.re)).count, PACommand.leads.count)
    }

    func testBadLinesDoNotStopThePA() {
        let (e, out, _) = makeEngine()
        e.receive(Data("not json".utf8))
        e.receive(Data(#"{"type":"surprise"}"#.utf8))
        e.receive(Data(#"{"type":"command"}"#.utf8))
        e.receive(Data(#"{"type":"command","id":"1","lead":"sing","text":"x"}"#.utf8))
        XCTAssertEqual(out.take().map(\.text), ["The PA does not know this command."])
    }

    func testLeadMatchIgnoresSpacesAndCase() {
        XCTAssertEqual(PACommand.from(lead: "to do"), .todo)
        XCTAssertEqual(PACommand.from(lead: "What's due"), .whatIsDue)
        XCTAssertEqual(PACommand.from(lead: "Remind me"), .remindMe)
        XCTAssertNil(PACommand.from(lead: "search my"))
    }

    func testMessageLines() {
        let line = Outgoing.list("1", "Due", ["a \"b\"\nc"]).line()
        XCTAssertFalse(line.contains(0x0A))
        XCTAssertEqual(Incoming.parse(Data(#"{"type":"hello","contract":1}"#.utf8)), .hello(contract: 1))
        XCTAssertEqual(Incoming.parse(Data(#"{"type":"command","id":"9","lead":"note","text":"hi","context":{"app":"x","n":3}}"#.utf8)),
                       .command(id: "9", lead: "note", text: "hi", context: ["app": "x"]))
    }

    func testPluginJsonLeadsAreTheLeadsOfTheProgram() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertEqual(Set(obj["leads"] as! [String]), Set(PACommand.leads.keys))
        XCTAssertEqual(obj["network"] as? [String], [])
        XCTAssertEqual(obj["id"] as? String, "pa")
    }
}
