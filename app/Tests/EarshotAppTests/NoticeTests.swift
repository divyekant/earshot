import EarshotCore
import EarshotUI
import XCTest
@testable import EarshotApp

/// The banners of the panel and the mark on the menu bar icon (design canvas "Panel A", "Window: States").
final class NoticeTests: XCTestCase {
    private func plugin(_ id: String, approved: Bool, on: Bool = true, problems: [String] = []) -> PluginEntry {
        PluginEntry(manifest: PluginManifest(id: id, name: id.capitalized, leads: ["x"], run: ["./x"]),
                    folder: URL(fileURLWithPath: "/tmp/\(id)"), hash: "h2", approved: approved, problems: problems, on: on)
    }

    func testNothingNeedsYou() {
        let n = AppController.notices(access: .granted, mic: .granted, plugins: [plugin("planner", approved: true)],
                                      approvals: ["planner": "h2"], stopped: { _ in nil }, wakeDownload: nil, speechProblem: nil)
        XCTAssertEqual(n, [])
    }

    func testEachProblemIsOneNotice() {
        let plugins = [plugin("planner", approved: false), plugin("helper", approved: false), plugin("broken", approved: false, problems: ["p"]),
                       plugin("runner", approved: true), plugin("quiet", approved: true, on: false)]
        let n = AppController.notices(access: .denied, mic: .denied, plugins: plugins, approvals: ["helper": "h1"],
                                      stopped: { _ in "It stopped 3 times in 1 minute." }, wakeDownload: 0.4,
                                      speechProblem: "Speech did not load: no model")
        XCTAssertEqual(n.map(\.id), ["mic", "access", "speech", "plugin-planner", "plugin-helper", "stopped-runner", "wake-download"])
        XCTAssertEqual(n.first?.main, true)
        XCTAssertEqual(n[2].detail, "no model")
        XCTAssertEqual(n[3].title, "Planner waits for you")
        XCTAssertEqual(n[4].title, "Helper changed")
        XCTAssertEqual(n.last?.kind, .working)
        XCTAssertEqual(n.last?.progress, 0.4)
    }
}
