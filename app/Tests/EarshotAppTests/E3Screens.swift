import AppKit
import EarshotActions
import EarshotCore
import EarshotRouter
import XCTest

// E3: the screenshot fallback (D-10) on real screens. It never clicks and never presses a key.
// For each case it opens a page or an app, reads the front window, routes the command with the rules,
// then asks Jev with the marked picture and reports what earshot would click. It skips unless
// EARSHOT_E3_CASES names a JSON file. The Jev key comes from EARSHOT_E3_KEY_CMD (a shell command that prints it);
// the key is never printed or saved. Results go to EARSHOT_E3_OUT (JSON lines).
//
//   EARSHOT_E3_CASES=cases.json EARSHOT_E3_OUT=e3.jsonl \
//   EARSHOT_E3_KEY_CMD='security find-generic-password -s earshot -a jev-api-key -w' \
//   swift test --filter E3Screens
//
// Case: {"name": "...", "open": "https://... or a bundle id", "command": "...", "expect": ["label part", ...],
//        "waitMs": 2500}. An empty "expect" means: the right answer is no target.

struct E3Case: Codable {
    var name: String
    var open: String?
    var command: String
    var expect: [String]
    var waitMs: Int?
}

final class E3Screens: XCTestCase {
    @MainActor
    func testE3() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let casesPath = env["EARSHOT_E3_CASES"] else { throw XCTSkip("set EARSHOT_E3_CASES to run E3") }
        let cases = try JSONDecoder().decode([E3Case].self, from: Data(contentsOf: URL(fileURLWithPath: casesPath)))
        let key = try XCTUnwrap(Self.key(env["EARSHOT_E3_KEY_CMD"]), "no Jev key")
        let picker = JevScreenPicker(apiKey: key)
        let runner = EarshotActionRunner(store: nil)
        let out = env["EARSHOT_E3_OUT"].map { URL(fileURLWithPath: $0) }
        var lines: [String] = []

        for c in cases {
            if let target = c.open { Self.open(target) }
            try? await Task.sleep(nanoseconds: UInt64(c.waitMs ?? 2500) * 1_000_000)
            let screen = await runner.screen()
            let context = RouteContext(apps: [], names: [], frontBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                       screen: screen)
            let rules = await CommandRouter().route(c.command, context: context)
            let t0 = Date()
            let v = await runner.visionTarget(c.command, mode: .hold, picker: picker, budgetMs: 5000)
            let ms = Date().timeIntervalSince(t0) * 1000
            let label = v.label.lowercased()
            let right = c.expect.isEmpty ? v.elementID == nil
                : v.elementID != nil && c.expect.contains { label.contains($0.lowercased()) }
            let rulesLabel: String = {
                if case .click(let id) = rules.intent { return screen?.elements.first { $0.id == id }?.label ?? id }
                return "\(rules.intent)"
            }()
            let row: [String: Any] = [
                "name": c.name, "command": c.command, "expect": c.expect, "front": context.frontBundleID ?? "",
                "elements": screen?.elements.count ?? 0,
                "rules": rulesLabel, "rulesConfidence": rules.confidence,
                "pick": v.elementID ?? "none", "label": v.label, "note": v.note, "right": right,
                "ms": (ms * 10).rounded() / 10, "stages": v.stages,
            ]
            let line = String(data: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), encoding: .utf8) ?? ""
            print("E3 \(line)")
            lines.append(line)
        }
        if let out { try lines.joined(separator: "\n").appending("\n").write(to: out, atomically: true, encoding: .utf8) }
    }

    static func key(_ command: String?) -> String? {
        guard let command else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let k = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return k?.isEmpty == false ? k : nil
    }

    /// Opens a web address in the default browser, or an app by its bundle id. It presses no key.
    @MainActor
    static func open(_ target: String) {
        if target.hasPrefix("https://") || target.hasPrefix("http://"), let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
