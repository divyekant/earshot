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

    /// Puts Finder in front, so that each run starts from another app, as a voice command does.
    private func frontFinder() async {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }?.activate()
        try? await Task.sleep(nanoseconds: 800_000_000)
    }
}
