@testable import EarshotCore
import XCTest

/// The command line: settings by name, the words, and the refusals (R-CT-1 to R-CT-4).
final class ControlTests: XCTestCase {
    private var folder: URL!
    private var sent: [ControlRequest] = []

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sent = []
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func tool(running: Bool = true, trusted: Bool = true) -> ControlTool {
        ControlTool(store: Store(folder: folder), send: { [unowned self] request in
            sent.append(request)
            return running ? ControlReply(ok: true, lines: ["ok \(request.cmd)"]) : nil
        }, callerTrusted: { trusted })
    }

    func testListHasEverySetting() {
        let keys = ControlSettings.list(EarshotSettings()).map(\.key)
        XCTAssertTrue(keys.contains("mode"))
        XCTAssertTrue(keys.contains("voiceGate"))
        XCTAssertEqual(keys, keys.sorted())
    }

    func testSetEachKind() throws {
        var s = EarshotSettings()
        s = try ControlSettings.set(s, "mode", "alwaysOn", ownerOK: false)
        XCTAssertEqual(s.mode, .alwaysOn)
        s = try ControlSettings.set(s, "playSounds", "off", ownerOK: false)
        XCTAssertFalse(s.playSounds)
        s = try ControlSettings.set(s, "voiceGate", "0.3", ownerOK: false)
        XCTAssertEqual(s.voiceGate, 0.3)
        s = try ControlSettings.set(s, "voiceGate", "1", ownerOK: false)
        XCTAssertEqual(s.voiceGate, 1)
        s = try ControlSettings.set(s, "tier2BudgetMs", "800", ownerOK: false)
        XCTAssertEqual(s.tier2BudgetMs, 800)
        s = try ControlSettings.set(s, "wakePhrase", "hey atlas", ownerOK: false)
        XCTAssertEqual(s.wakePhrase, "hey atlas")
        XCTAssertEqual(try ControlSettings.get(s, "wakePhrase"), "\"hey atlas\"")
        XCTAssertEqual(try ControlSettings.get(s, "playSounds"), "false")
    }

    func testBadValuesAreRefused() {
        let s = EarshotSettings()
        XCTAssertThrowsError(try ControlSettings.set(s, "mode", "sometimes", ownerOK: false)) { error in
            XCTAssertTrue("\(error)".contains("hold, alwaysOn"), "\(error)")
        }
        XCTAssertThrowsError(try ControlSettings.set(s, "playSounds", "maybe", ownerOK: false))
        XCTAssertThrowsError(try ControlSettings.set(s, "tier2BudgetMs", "0.5", ownerOK: false))
        XCTAssertThrowsError(try ControlSettings.set(s, "voiceGate", "high", ownerOK: false))
        XCTAssertThrowsError(try ControlSettings.set(s, "noSuchSetting", "1", ownerOK: false))
    }

    /// The cloud settings turn on only with --owner-ok (R-MD-1). Turning them off needs nothing.
    func testCloudSettingsNeedTheOwner() throws {
        var s = EarshotSettings()
        XCTAssertThrowsError(try ControlSettings.set(s, "tier2", "jev", ownerOK: false))
        XCTAssertThrowsError(try ControlSettings.set(s, "jevSeesScreen", "true", ownerOK: false))
        s = try ControlSettings.set(s, "tier2", "jev", ownerOK: true)
        XCTAssertEqual(s.tier2, .jev)
        s = try ControlSettings.set(s, "tier2", "off", ownerOK: false)
        XCTAssertEqual(s.tier2, .off)
    }

    /// Each setting that is not a number, a boolean or free text has a list of values.
    func testEveryChoiceSettingHasItsList() {
        for child in Mirror(reflecting: EarshotSettings()).children {
            guard let label = child.label else { continue }
            let plain = child.value is Bool || child.value is Int || child.value is UInt32 || child.value is Double
                || child.value is String
            if !plain { XCTAssertNotNil(ControlSettings.choices[label], "no choices for \(label)") }
        }
    }

    func testReset() throws {
        var s = EarshotSettings()
        s.voiceGate = 0.2
        s = try ControlSettings.reset(s, "voiceGate")
        XCTAssertEqual(s.voiceGate, EarshotSettings().voiceGate)
    }

    func testSetSavesAndTellsTheApp() {
        let out = tool().run(["settings", "set", "mode", "alwaysOn"])
        XCTAssertEqual(out.code, 0)
        XCTAssertEqual(out.lines.first, "mode = \"alwaysOn\"")
        XCTAssertEqual(Store(folder: folder).settings.mode, .alwaysOn)
        XCTAssertEqual(sent.map(\.cmd), ["reload"])
    }

    func testSetWorksWhenTheAppDoesNotRun() {
        let out = tool(running: false).run(["settings", "set", "playSounds", "false"])
        XCTAssertEqual(out.code, 0)
        XCTAssertFalse(Store(folder: folder).settings.playSounds)
        XCTAssertTrue(out.lines.last!.contains("next start"))
    }

    func testSetKeepsTheOtherSettings() throws {
        var s = EarshotSettings()
        s.wakePhrase = "hey atlas"
        try Store(folder: folder).save(s, "settings.json")
        _ = tool().run(["settings", "set", "playSounds", "false"])
        XCTAssertEqual(Store(folder: folder).settings.wakePhrase, "hey atlas")
    }

    func testPluginApprovalIsRefused() throws {
        let out = tool().run(["plugins", "approve", "pa"])
        XCTAssertEqual(out.code, 1)
        XCTAssertTrue(out.lines[0].contains("Manage > Plugins"))
        XCTAssertNil(Store(folder: folder).load([String: String].self, PluginContract.approvalsFile))
        XCTAssertTrue(sent.isEmpty)
    }

    func testPluginsListReadsTheFolder() throws {
        let dir = folder.appendingPathComponent("plugins/pa", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"contract":1,"id":"pa","name":"Helper","leads":["note"],"run":["/bin/cat"]}"#.utf8)
            .write(to: dir.appendingPathComponent("plugin.json"))
        let out = tool().run(["plugins"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.lines[0].hasPrefix("pa "), out.lines[0])
        XCTAssertTrue(out.lines[0].contains("not approved"))
    }

    func testRunIsADryRunByDefault() {
        let out = tool().run(["run", "open", "notes"])
        XCTAssertEqual(out.code, 0)
        XCTAssertEqual(sent, [ControlRequest(cmd: "run", text: "open notes", actions: false, wait: 3)])
    }

    func testRunWithActionsNeedsAccessibility() {
        let out = tool(trusted: false).run(["run", "--actions", "open", "notes"])
        XCTAssertEqual(out.code, 1)
        XCTAssertTrue(sent.isEmpty)
        _ = tool().run(["run", "todo", "milk", "--actions", "--wait", "5"])
        XCTAssertEqual(sent, [ControlRequest(cmd: "run", text: "todo milk", actions: true, wait: 5)])
    }

    func testRemoteCommandsWhenTheAppDoesNotRun() {
        let out = tool(running: false).run(["status"])
        XCTAssertEqual(out.code, 1)
        XCTAssertTrue(out.lines[0].contains("does not run"))
    }

    func testOnlyControlWordsStartTheCommandLine() {
        XCTAssertTrue(ControlTool.isControl(["settings"]))
        XCTAssertTrue(ControlTool.isControl(["status"]))
        XCTAssertFalse(ControlTool.isControl([]))
        XCTAssertFalse(ControlTool.isControl(["-psn_0_1234"]))
        XCTAssertFalse(ControlTool.isControl(["-NSDocumentRevisionsDebugMode", "YES"]))
    }
}
