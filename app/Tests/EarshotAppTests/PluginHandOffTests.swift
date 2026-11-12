import EarshotActions
@testable import EarshotApp
import EarshotCore
import EarshotRouter
import XCTest

/// A fake hand-off: it keeps each call.
final class FakePlugins: PluginHandOff {
    var leads: [PluginLead] = [PluginLead(pluginID: "pa", lead: "remind me to")]
    var targetNames: [PluginTargetName] = []
    var keys = ["app"]
    func contextKeys(of pluginID: String) -> [String] { keys }
    var calls: [(String, String, String, [String: String])] = []
    var reason: String?
    func name(of pluginID: String) -> String { "Helper" }
    func handOff(pluginID: String, lead: String, text: String, available: [String: String]) -> String? {
        calls.append((pluginID, lead, text, available))
        return reason
    }
}

/// A front window with a document and a selection. It counts the reads of the two keys.
final class FocusRunner: CommandActions {
    var reads: [(Bool, Bool)] = []
    var signIn = false
    func screen() async -> ScreenSnapshot? {
        ScreenSnapshot(bundleID: "com.apple.Preview", windowTitle: signIn ? "Sign in" : "lease.pdf",
                       url: signIn ? "https://accounts.example.com/signin" : nil,
                       elements: signIn ? [ScreenElement(id: "e1", role: "AXTextField", subrole: "AXSecureTextField",
                                                         label: "Password", risky: false)] : [])
    }
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        ActionOutcome(ok: true, note: "", stages: [:])
    }
    func pluginFocus(document: Bool, selection: Bool) async -> PluginFocus {
        reads.append((document, selection))
        return PluginFocus(document: document ? "/Users/me/lease.pdf" : nil, selection: selection ? "the blue fox" : nil)
    }
}

/// The hand-off in the command path, and the plugin host with a real program (R-PL-1 to R-PL-5).
/// Made-up text only.
final class PluginHandOffTests: XCTestCase {
    private func pipeline(_ plugins: PluginHandOff?, runner: FieldRunner = FieldRunner()) -> (CommandPipeline, TextEngine) {
        let engine = TextEngine()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.anthropic.claudefordesktop" })
        p.plugins = plugins
        return (p, engine)
    }

    func testLeadHandsOffAndDoesNoAction() async {
        let fake = FakePlugins()
        let runner = FieldRunner()
        let (p, e) = pipeline(fake, runner: runner)
        e.text = "Remind me to open Slack and water the plants."
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(fake.calls.first?.2, "open Slack and water the plants")
        XCTAssertTrue(runner.runs.isEmpty, "a plugin command never clicks or types (R-PL-3)")
        XCTAssertEqual(r.heard, "remind me to (6 words)", "the log keeps the lead and a word count, not the words")
        XCTAssertFalse(r.note.contains("plants"), r.note)
        XCTAssertNotNil(r.stages["plugin.handoff"])
        XCTAssertEqual(fake.calls.first?.3["app"], "com.anthropic.claudefordesktop")
    }

    /// "open today" runs the core open action with the target of the plugin. The plugin gets no command (R-PL-3).
    func testOpenTargetIsTheCoreOpen() async {
        let fake = FakePlugins()
        fake.targetNames = [PluginTargetName(pluginID: "pa", name: "today", open: "/tmp/pa/today.html")]
        let runner = FieldRunner()
        let (p, e) = pipeline(fake, runner: runner)
        e.text = "Open today."
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(runner.runs.first?.0, .openTarget(pluginID: "pa", name: "today", open: "/tmp/pa/today.html"))
        XCTAssertTrue(fake.calls.isEmpty)
    }

    /// "document" and "selection" go to a plugin that names them, and the log keeps no value (docs/PLUGINS.md 5.1).
    func testDocumentAndSelection() async {
        let fake = FakePlugins()
        fake.keys = ["app", "document", "selection"]
        let runner = FocusRunner()
        let engine = TextEngine()
        let p = CommandPipeline(engine: engine, router: CommandRouter(), actions: runner, names: FakeNames(),
                                apps: { Fixture.apps }, allNames: { Fixture.names }, frontBundleID: { "com.apple.Preview" })
        p.plugins = fake
        engine.text = "remind me to read this"
        let r = await p.finish(mode: .hold)
        XCTAssertTrue(r.ok, r.note)
        XCTAssertEqual(fake.calls.first?.3["document"], "/Users/me/lease.pdf")
        XCTAssertEqual(fake.calls.first?.3["selection"], "the blue fox")
        XCTAssertNotNil(r.stages["plugin.context"])
        XCTAssertFalse(r.note.contains("blue fox") || r.heard.contains("blue fox") || r.note.contains("lease"), "no value in the log")

        // A plugin that does not name the keys: no read.
        fake.keys = ["app"]
        runner.reads = []
        engine.text = "remind me to read this"
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(runner.reads.isEmpty)

        // A sign-in page: no read and no context.
        fake.keys = ["app", "document", "selection"]
        runner.signIn = true
        engine.text = "remind me to read this"
        _ = await p.finish(mode: .hold)
        XCTAssertTrue(runner.reads.isEmpty)
        XCTAssertEqual(fake.calls.last?.3, [:])
    }

    func testFailedHandOffShowsTheReason() async {
        let fake = FakePlugins()
        fake.reason = "the plugin Helper did not start"
        let (p, e) = pipeline(fake)
        e.text = "remind me to stretch"
        let r = await p.finish(mode: .hold)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.note.hasPrefix("the plugin Helper did not start"), r.note)
    }

    /// With no plugins, a lead is plain words: with the hold key and a focused field, dictation types them.
    func testNoPluginsIsDictation() async {
        let runner = FieldRunner()
        let (p, e) = pipeline(nil, runner: runner)
        e.text = "remind me to stretch"
        _ = await p.finish(mode: .hold)
        XCTAssertEqual(runner.runs.first?.0, .typeText("remind me to stretch"))
    }

    /// No context on a sign-in, code or payment page.
    func testNoContextOnASensitivePage() {
        let screen = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Sign in", url: "https://accounts.example.com/signin",
                                    elements: [ScreenElement(id: "e1", role: "AXTextField", subrole: "AXSecureTextField",
                                                             label: "Password", risky: false)])
        let context = RouteContext(apps: [], names: [], frontBundleID: "com.google.Chrome", screen: screen)
        XCTAssertEqual(CommandPipeline.pluginContext(context), [:])
        let plain = RouteContext(apps: [], names: [], frontBundleID: "com.apple.Notes")
        XCTAssertEqual(CommandPipeline.pluginContext(plain), ["app": "com.apple.Notes"])
    }

    // MARK: - The host, with a real program

    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    /// Writes a plugin folder and approves it. Returns the host, read.
    private func install(_ id: String, run: [String], script: String? = nil, context: [String] = ["app"],
                         approve: Bool = true) throws -> PluginHost {
        let dir = folder.appendingPathComponent("plugins/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let script {
            let file = dir.appendingPathComponent("plugin.sh")
            try Data(script.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let manifest = PluginManifest(id: id, name: "Echo", leads: ["note"], context: context, run: run)
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("plugin.json"))
        let store = Store(folder: folder)
        if approve, let entry = PluginCatalog(store: store).scan().first { try PluginCatalog(store: store).setApproved(entry, true) }
        let host = PluginHost(store: store)
        host.reload()
        return host
    }

    /// The test plugin: it answers each command with the number of its words, and gives one target.
    private let echo = """
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *'"type":"command"'*)
          id=$(printf '%s' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
          printf '{"type":"answer","re":"%s","kind":"note","text":"kept"}\\n' "$id"
          printf '{"type":"targets","targets":[{"id":"t1","name":"stamps","kind":"todo"}]}\\n'
          ;;
      esac
    done
    """

    func testHostRoundTrip() throws {
        let host = try install("echo", run: ["./plugin.sh"], script: echo)
        defer { host.stopAll() }
        XCTAssertEqual(host.leads, [PluginLead(pluginID: "echo", lead: "note")])
        let answered = expectation(description: "answer")
        var got: PluginMessage?
        host.onAnswer = { message, manifest in
            XCTAssertEqual(manifest.id, "echo")
            got = message
            answered.fulfill()
        }
        XCTAssertNil(host.handOff(pluginID: "echo", lead: "note", text: "buy stamps", available: ["app": "a", "url": "https://x.example"]))
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(got?.shownText, "kept")
        XCTAssertNotNil(got?.re)
        // The targets come after the answer, on the same line order.
        let deadline = Date().addingTimeInterval(2)
        while host.targets(of: "echo").isEmpty, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(host.targets(of: "echo"), [PluginTarget(id: "t1", name: "stamps", kind: "todo")])
    }

    func testNotApprovedDoesNotStart() throws {
        let host = try install("echo", run: ["./plugin.sh"], script: echo, approve: false)
        XCTAssertTrue(host.leads.isEmpty)
        XCTAssertNotNil(host.handOff(pluginID: "echo", lead: "note", text: "x", available: [:]))
    }

    /// A plugin that never reads cannot slow a command (R-PL-5).
    func testHandOffDoesNotWait() throws {
        let host = try install("sleeper", run: ["/bin/sleep", "30"])
        defer { host.stopAll() }
        let t0 = Date()
        for i in 0..<200 {
            XCTAssertNil(host.handOff(pluginID: "sleeper", lead: "note", text: String(repeating: "word ", count: 200) + "\(i)", available: [:]))
        }
        let ms = Date().timeIntervalSince(t0) * 1000
        print("plugin hand-off: \(String(format: "%.3f", ms / 200)) ms each")
        XCTAssertLessThan(ms / 200, 5)
    }

    /// A plugin that stops at once is started again at most `maxStarts` times, then it is off.
    func testStartLimit() throws {
        let host = try install("quitter", run: ["/usr/bin/true"])
        defer { host.stopAll() }
        var last: String?
        for _ in 0..<20 {
            last = host.handOff(pluginID: "quitter", lead: "note", text: "x", available: [:])
            if last != nil { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(last?.contains("it is off") == true, last ?? "nil")
    }

    /// A new build of the program, with the same plugin.json: "Read again" (reload) starts the new program.
    /// The approval stays.
    func testNewProgramStartsOnReload() throws {
        let host = try install("echo", run: ["./plugin.sh"], script: echo)
        defer { host.stopAll() }
        func answer() -> String? {
            let answered = expectation(description: "answer")
            var got: String?
            host.onAnswer = { message, _ in got = message.shownText; answered.fulfill() }
            XCTAssertNil(host.handOff(pluginID: "echo", lead: "note", text: "x", available: [:]))
            wait(for: [answered], timeout: 5)
            host.onAnswer = nil
            return got
        }
        XCTAssertEqual(answer(), "kept")
        let file = folder.appendingPathComponent("plugins/echo/plugin.sh")
        try Data(echo.replacingOccurrences(of: "kept", with: "new build").utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        host.reload()
        XCTAssertEqual(host.leads, [PluginLead(pluginID: "echo", lead: "note")], "the approval stays")
        XCTAssertEqual(answer(), "new build")
    }

    /// A changed manifest stops the plugin and needs a new approval.
    func testChangedManifestNeedsApproval() throws {
        let host = try install("echo", run: ["./plugin.sh"], script: echo)
        defer { host.stopAll() }
        let file = folder.appendingPathComponent("plugins/echo/plugin.json")
        var m = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: file))
        m.leads = ["note", "list"]
        try JSONEncoder().encode(m).write(to: file)
        host.reload()
        XCTAssertTrue(host.leads.isEmpty)
    }
}
