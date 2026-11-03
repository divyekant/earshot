import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// A runner whose screen is earshot's own window, and that records the order of the calls.
final class OwnWindowRunner: CommandActions {
    var events: [String] = []
    var runs: [Intent] = []
    var bundleID = "com.divyekant.earshot"
    func screen() async -> ScreenSnapshot? {
        events.append("screen")
        return ScreenSnapshot(bundleID: bundleID, windowTitle: "Manage", elements: [
            ScreenElement(id: "e1", role: "AXButton", label: "Discover apps", risky: false)])
    }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        runs.append(intent)
        return ActionOutcome(ok: true, note: "dry run")
    }
}

final class FrontAppTests: XCTestCase {
    private func make(_ text: String, runner: OwnWindowRunner, front: String) -> CommandPipeline {
        let engine = TextEngine()
        engine.text = text
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { front })
        p.ownBundleID = "com.divyekant.earshot"
        return p
    }

    func testRestoreRunsBeforeTheScreenRead() async {
        let runner = OwnWindowRunner()
        runner.bundleID = "com.google.Chrome"
        let p = make("click discover apps", runner: runner, front: "com.google.Chrome")
        p.restoreFront = { runner.events.append("restore"); return 120 }
        let r = await p.finish(mode: .hold)
        XCTAssertEqual(runner.events, ["restore", "screen"])
        XCTAssertEqual(r.stages["front.restore"], 120)
    }

    func testNoStageWhenEarshotWasNotInFront() async {
        let runner = OwnWindowRunner()
        let r = await make("open notes", runner: runner, front: "com.google.Chrome").finish(mode: .hold)
        XCTAssertNil(r.stages["front.restore"])
    }

    func testOwnWindowIsNeverATarget() async {
        let runner = OwnWindowRunner()
        let r = await make("click discover apps", runner: runner, front: "com.divyekant.earshot").finish(mode: .hold)
        XCTAssertTrue(runner.runs.isEmpty, "earshot must not press its own Manage window by voice: \(r.note)")
        XCTAssertTrue(r.note.contains("screen: none, front unknown"), r.note)
        // Commands that do not need the screen still work.
        let open = OwnWindowRunner()
        _ = await make("open notes", runner: open, front: "com.divyekant.earshot").finish(mode: .hold)
        XCTAssertEqual(open.runs.first, .openApp(appID: "notes"))
    }

    /// The tracker skips its own app, whatever app is in front on the Mac. A failed run of the old test: the
    /// owner's earshot window was in front during `swift test`.
    func testTrackerSkipsItsOwnApp() async throws {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != nil }
        guard let own = apps.first, let other = apps.first(where: { $0.bundleIdentifier != own.bundleIdentifier }) else {
            throw XCTSkip("needs two running apps with a bundle id")
        }
        let t = FrontTracker(own: own.bundleIdentifier, current: nil, frontBundleID: { "com.example.other-front" })
        t.activated(own)
        XCTAssertNil(t.lastBundleID, "the tracker skips its own app")
        t.activated(other)
        XCTAssertEqual(t.lastBundleID, other.bundleIdentifier)
        let notInFront = await t.restore()
        XCTAssertNil(notInFront, "its own app is not in front, so there is nothing to restore")

        // Its own app in front, and no other app known: nothing to activate, and it returns at once.
        let alone = FrontTracker(own: own.bundleIdentifier, current: nil, frontBundleID: { own.bundleIdentifier })
        alone.activated(own)
        XCTAssertNil(alone.lastBundleID)
        let waited = await alone.restore()
        XCTAssertNotNil(waited)
        XCTAssertLessThan(waited ?? 1e9, 100)
    }
}
