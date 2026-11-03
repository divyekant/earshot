import EarshotCore
import Foundation
import XCTest
@testable import EarshotRouter

/// Replays heard text through the rules router, for the command test set (I-28, I-29).
/// It runs only if EARSHOT_REPLAY names a JSONL file with a "heard" field on each line. Else it does nothing.
/// It uses the owner's app table (Store().apps) and no screen, so screen commands show only the parse.
/// It writes one JSON line for each record to EARSHOT_REPLAY_OUT (default: <input>.out.jsonl). No audio.
final class ReplayTests: XCTestCase {
    func testReplay() throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["EARSHOT_REPLAY"] else { return }
        let output = env["EARSHOT_REPLAY_OUT"] ?? input + ".out.jsonl"
        let apps = Store().apps
        let context = RouteContext(apps: apps, names: [])
        var lines: [String] = []
        for line in try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n") {
            guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let heard = obj["heard"] as? String, !heard.isEmpty else { continue }
            let t0 = DispatchTime.now().uptimeNanoseconds
            let d = CommandRouter.rules(heard, context: context)
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000
            let parse = ScreenRouter.parse(heard)
            let row: [String: Any] = [
                "heard": heard,
                "intent": ReplayText.describe(d.intent, apps: apps),
                "sure": d.sure,
                "why": d.why,
                "isCommand": CommandRouter.hasCommandWord(heard, context: context),
                "parseKind": "\(parse.kind)",
                "parseTarget": parse.target.joined(separator: " "),
                "ms": ms,
            ]
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            lines.append(String(decoding: data, as: UTF8.self))
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: output, atomically: true, encoding: .utf8)
        print("replay: \(lines.count) records -> \(output), apps: \(apps.count)")
    }
}

/// The router tests do not depend on EarshotUI, so the replay names the intent itself.
enum ReplayText {
    static func describe(_ intent: Intent, apps: [AppEntry]) -> String {
        switch intent {
        case .openApp(let id): return "openApp " + (apps.first { $0.id == id }?.name ?? id)
        default: return "\(intent)"
        }
    }
}
