import EarshotCore
@testable import EarshotRouter
import Foundation
import XCTest

/// The leads of the PA plugin (plugins/pa/plugin.json) pass the lead check of earshot (R-PL-4, phase1-build-spec,
/// section 6). If a lead fails here, the Plugins tab refuses it on the Mac.
final class PAPluginLeadsTests: XCTestCase {
    /// The test apps, and app names that are near a PA lead.
    let apps = Fixtures.apps + [
        AppEntry(id: "reminders", name: "Reminders", bundleID: "com.apple.reminders", aliases: ["reminders"], approved: true),
        AppEntry(id: "dropbox", name: "Dropbox", bundleID: "com.getdropbox.dropbox", aliases: ["dropbox"], approved: true),
        AppEntry(id: "todoist", name: "Todoist", bundleID: "com.todoist.mac.Todoist", aliases: ["todoist"], approved: true),
        AppEntry(id: "things", name: "Things 3", bundleID: "com.culturedcode.ThingsMac", aliases: ["things"], approved: true),
    ]

    func manifest() throws -> PluginManifest {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugins/pa/plugin.json")
        return try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: url))
    }

    func testEachLeadIsAccepted() throws {
        let m = try manifest()
        XCTAssertEqual(m.problems, [])
        for lead in m.leads {
            XCTAssertNil(PluginRouter.refusal(lead, apps: apps), "earshot refuses the lead \"\(lead)\"")
        }
        let usable = PluginRouter.usable(m.leads.map { PluginLead(pluginID: m.id, lead: $0) }, apps: apps)
        XCTAssertEqual(usable.count, m.leads.count)
    }

    func testSpokenFormsReachThePA() throws {
        let m = try manifest()
        let leads = m.leads.map { PluginLead(pluginID: m.id, lead: $0) }
        let cases: [(String, String, String)] = [
            ("Remind me to call the plumber at 5.", "remind me", "to call the plumber at 5"),
            ("To do send the tax papers by Friday", "todo", "send the tax papers by Friday"),
            ("What's due?", "what due", ""),
            ("Where is the tile quote", "where is", "the tile quote"),
            ("done 2", "done", "2"),
            ("note the landlord wants two months notice", "note", "the landlord wants two months notice"),
        ]
        for (text, lead, rest) in cases {
            let m = PluginRouter.match(text, plugins: leads, apps: apps)
            XCTAssertEqual(m?.lead.lead, lead, text)
            XCTAssertEqual(m?.rest, rest, text)
        }
        // "where's" reads as "where": no lead, so a dictated question stays dictation.
        XCTAssertNil(PluginRouter.match("Where's my coat", plugins: leads, apps: apps))
        // "search my" is a core word: earshot refuses it, so it is not a lead of the PA.
        XCTAssertNotNil(PluginRouter.refusal("search my", apps: apps))
    }
}
