import AppKit
import EarshotCore
@testable import EarshotActions
import XCTest

/// A live bench for the chat flow (R-SP-1, R-NV-6). It opens the owner's own chat in each chat app of the
/// owner's catalogue and stops at the focused message box. It types no text and presses no Send.
///
/// It runs only on the owner's Mac, with `EARSHOT_LIVE_CHAT=1`, from a terminal that has the Accessibility
/// permission. CI skips it. It reads `apps.json`, `names.json` and `focus-methods.json` from the store folder,
/// and it writes nothing there: the learned focus methods go to a temporary folder.
///
/// Environment:
/// - `EARSHOT_LIVE_CHAT=1`: run the bench.
/// - `EARSHOT_BENCH_RUNS`: runs for each app (default 5).
/// - `EARSHOT_BENCH_APPS`: app ids, separated by commas (default: every approved chat app with an own chat).
/// - `EARSHOT_BENCH_OUT`: a file for the results as JSON lines. The lines have no chat names.
@MainActor
final class ChatStageBench: XCTestCase {
    func testOwnChatStages() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["EARSHOT_LIVE_CHAT"] == "1" else { throw XCTSkip("live bench: set EARSHOT_LIVE_CHAT=1 on the owner's Mac") }
        guard AXIsProcessTrusted() else { throw XCTSkip("this process has no Accessibility permission") }

        let real = Store()
        let temp = Store(folder: FileManager.default.temporaryDirectory.appendingPathComponent("earshot-bench-\(UUID().uuidString)"))
        if let learned = real.load([String: String].self, EarshotActionRunner.learnedFile) {
            try temp.save(learned, EarshotActionRunner.learnedFile)
        }
        let apps = real.apps
        let names = real.names
        let runs = Int(env["EARSHOT_BENCH_RUNS"] ?? "") ?? 5
        let only = env["EARSHOT_BENCH_APPS"].map { Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }) }
        let outURL = env["EARSHOT_BENCH_OUT"].map { URL(fileURLWithPath: $0) }
        var lines: [String] = []

        let runner = EarshotActionRunner(options: ActionOptions(), store: temp)
        let context = RouteContext(apps: apps, names: names)
        for app in apps where app.isChat && app.approved && app.enabled && (only?.contains(app.id) ?? true) {
            guard let own = names.first(where: { $0.appID == app.id && $0.isSelf }) else {
                print("BENCH \(app.id): no own chat in names.json, skipped")
                continue
            }
            for run in 1...runs {
                await frontFinder()
                let t0 = Clock.nowNs()
                let out = await runner.run(.openChat(appID: app.id, target: own.name, text: nil), context: context)
                let wall = Clock.ms(since: t0)
                let safeNote = out.note.replacingOccurrences(of: own.name, with: "<own>")
                let stages = out.stages.sorted { $0.value < $1.value }.map { "\($0.key)=\(Int($0.value.rounded()))" }.joined(separator: " ")
                print("BENCH \(app.id) run \(run) ok=\(out.ok) wall=\(Int(wall.rounded())) \(stages) | \(safeNote)")
                let row: [String: Any] = ["app": app.id, "run": run, "ok": out.ok, "wall": wall, "stages": out.stages, "note": safeNote]
                if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) {
                    lines.append(s)
                }
            }
        }
        await frontFinder()
        if let outURL { try (lines.joined(separator: "\n") + "\n").write(to: outURL, atomically: true, encoding: .utf8) }
    }

    /// A look at the switcher list, for a failure study: it presses the switcher keys, types the name, and prints
    /// each row below the field with its role and whether it is selected. Then it presses Escape. It presses no Return.
    /// Set `EARSHOT_BENCH_DUMP` to an app id.
    func testSwitcherRows() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["EARSHOT_LIVE_CHAT"] == "1", let appID = env["EARSHOT_BENCH_DUMP"] else { throw XCTSkip("live dump only") }
        let store = Store()
        guard let e = store.apps.first(where: { $0.id == appID }), case .switcher(let keys) = e.openChat,
              let own = store.names.first(where: { $0.appID == appID && $0.isSelf }),
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: e.bundleID).first else { throw XCTSkip("no app") }
        running.activate()
        try await Task.sleep(nanoseconds: 700_000_000)
        let app = AX.appElement(running.processIdentifier)
        if e.electron { _ = AX.set(app, "AXManualAccessibility", kCFBooleanTrue) }
        print("DUMP focus before: \(AX.describeFocus(app))")
        if let combo = Keys.parse(keys) { Keys.press(combo) }
        try await Task.sleep(nanoseconds: 400_000_000)
        print("DUMP focus after keys: \(AX.describeFocus(app))")
        // A field that shows without focus (a new-chat panel): look for it for up to 2 s, then focus it.
        let tScan = Clock.nowNs()
        while Clock.ms(since: tScan) < 2000, let w = AX.window(app), let f = AX.focused(app), !AX.isSwitcherField(f, in: w) {
            if let field = AX.switcherFields(in: w, budgetMs: 60).first {
                print("DUMP field found at +\(Int(Clock.ms(since: tScan)) + 400) ms: \(AX.role(field)) \(AX.label(field)); focus set: \(AX.set(field, "AXFocused", kCFBooleanTrue))")
                try await Task.sleep(nanoseconds: 100_000_000)
                if !AX.same(AX.focused(app), field), let fr = AX.frame(field) {
                    print("DUMP focus did not move: click the field")
                    Mouse.click(CGPoint(x: fr.x + fr.w / 2, y: fr.y + fr.h / 2))
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        print("DUMP focus now: \(AX.describeFocus(app))")
        // Type only into a switcher field, never into a message box.
        guard let field0 = AX.focused(app), let win = AX.window(app), AX.isSwitcherField(field0, in: win),
              !AX.isComposer(field0, in: win), !AX.looksLikeComposer(field0) else {
            Keys.press(Keys.escape)
            throw XCTSkip("the focus is not in a switcher field: nothing typed")
        }
        let typedName = env["EARSHOT_BENCH_NAME"] ?? own.name
        let fieldFrame = AX.frame(field0)
        let before = fieldFrame.map { AX.textsBelow($0, app: app, skip: field0) } ?? []
        let baseline = ActionRules.matchKeys(before, name: typedName)
        print("DUMP baseline: \(before.count) texts, \(baseline.count) match keys: \(baseline.sorted())")
        Keys.type(typedName)
        for wait in [300, 600, 1000, 1500] {
            try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
            guard let field = AX.focused(app), let f = AX.frame(field) else { print("DUMP no focus"); continue }
            let below = AX.textsBelow(f, app: app, skip: field)
            print("DUMP t+\(wait) result=\(ActionRules.switcherResult(below, name: typedName, baseline: baseline))")
            for row in ActionRules.rows(below).prefix(6) {
                print("DUMP   ROW " + row.map { "\($0.0.prefix(40))@\(Int($0.1.y))h\(Int($0.1.h))" }.joined(separator: " ; "))
            }
            print("DUMP t+\(wait) field \(AX.role(field)) value=\(AX.value(field) ?? "-") active=\(AX.element(field, "AXActiveDescendant").map { AX.label($0) } ?? "-")")
            var queue = AX.elements(app, "AXWindows")
            var i = 0
            var rows = 0
            while i < queue.count, i < 4000, rows < 25 {
                let el = queue[i]; i += 1
                let r = AX.role(el)
                if let ef = AX.frame(el), ef.y >= f.maxY - 2, ef.y < f.maxY + 500, ef.x < f.maxX, ef.maxX > f.x,
                   ["AXRow", "AXCell", "AXButton", "AXLink", "AXMenuItem", "AXListItem", "AXOption", "AXGroup", "AXStaticText"].contains(r) {
                    let sel = AX.bool(el, "AXSelected").map { $0 ? "SEL" : "-" } ?? "?"
                    let text = [AX.string(el, "AXTitle"), AX.string(el, "AXDescription"), AX.value(el)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ")
                    if !text.isEmpty || sel == "SEL" {
                        print("DUMP   \(r)/\(AX.subrole(el)) \(sel) y=\(Int(ef.y)) \(String(text.prefix(80)))")
                        rows += 1
                    }
                }
                queue.append(contentsOf: AX.elements(el, "AXChildren"))
            }
        }
        Keys.press(Keys.escape)
    }

    /// Puts Finder in front, so that each run starts from another app, as a voice command does.
    private func frontFinder() async {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }?.activate()
        try? await Task.sleep(nanoseconds: 800_000_000)
    }
}
