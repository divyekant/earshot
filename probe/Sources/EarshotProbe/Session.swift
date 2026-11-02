import AppKit
import Carbon.HIToolbox
import Foundation

/// One line of the Part B script.
struct ScriptLine {
    let say: String
    let appID: String?
    let personName: String?

    var scored: Bool { appID != nil }

    static func make(apps: [AppRow], people: [Person]) -> [ScriptLine] {
        let phrases = ["running late", "on my way", "call me after lunch", "can we move the meeting",
                       "sounds good", "check the new design doc", "back in ten minutes", "send me the file please"]
        guard let me = people.first(where: { $0.me }) else { return [] }
        let others = people.filter { !$0.me }
        var perApp: [[ScriptLine]] = []
        for (a, app) in apps.enumerated() {
            var lines: [ScriptLine] = []
            for i in 0..<5 {
                let phrase = phrases[(a * 3 + i) % phrases.count]
                lines.append(ScriptLine(say: "\(app.spoken) me, \(phrase)", appID: app.id, personName: me.name))
            }
            let reachable = others.filter { $0.handles[app.id] != nil }
            for i in 0..<5 {
                if reachable.isEmpty {
                    lines.append(ScriptLine(say: "\(app.spoken) me", appID: app.id, personName: me.name))
                } else {
                    let p = reachable[i % reachable.count]
                    lines.append(ScriptLine(say: "\(app.spoken) \(p.name)", appID: app.id, personName: p.name))
                }
            }
            perApp.append(lines)
        }
        // Mix the apps, so that most commands start from another app.
        var mixed: [ScriptLine] = []
        for i in 0..<10 {
            for lines in perApp where i < lines.count { mixed.append(lines[i]) }
        }
        let free = [
            "Your own words: message yourself in any app",
            "Your own words: open a chat with a real contact",
            "Your own words: any command you would use every day",
            "Your own words: a long name or a hard name",
            "Your own words: one more of your choice",
        ]
        mixed += free.map { ScriptLine(say: $0, appID: nil, personName: nil) }
        return mixed
    }
}

/// Part B: hold the talk key, speak, release. The probe transcribes, routes and acts.
@MainActor
final class ListenSession {
    let router: Router
    let pipeline: Pipeline
    let listener: Listener
    let overlay = Overlay()
    let log: RunLog
    let script: [ScriptLine]
    private var index = 0
    private var recording = false
    private var busy = false
    private var lastID = 0
    private var count = 0
    private var focusTimes: [Double] = []

    static let talkID: UInt32 = 1
    static let markID: UInt32 = 2
    static let quitID: UInt32 = 3

    init(router: Router, pipeline: Pipeline, listener: Listener, log: RunLog, script: [ScriptLine]) {
        self.router = router
        self.pipeline = pipeline
        self.listener = listener
        self.log = log
        self.script = script
    }

    func start() {
        HotKeys.handler = { [weak self] id, pressed in self?.hotKey(id, pressed) }
        HotKeys.install()
        let mods = HotKeys.control | HotKeys.option
        let talk = HotKeys.register(id: Self.talkID, key: kVK_ANSI_E, modifiers: mods)
        HotKeys.register(id: Self.markID, key: kVK_ANSI_N, modifiers: mods)
        HotKeys.register(id: Self.quitID, key: kVK_ANSI_Q, modifiers: mods)
        if !talk { print("Could not register Control-Option-E. Another app uses it.") }
        listener.onVolatile = { [weak self] partial in
            Task { @MainActor in self?.overlay.show("● \(partial)") }
        }
        print("""

        Ready. Hold Control-Option-E, say the line, then release the keys.
        Control-Option-N marks the last result as wrong. Control-Option-Q ends the session.
        Log: \(log.url.path)

        """)
        showNext()
    }

    private func showNext(prefix: String = "") {
        guard index < script.count else {
            overlay.show(prefix + "Script done. Say more commands, or press Control-Option-Q.")
            print("Script done. You can go on with your own commands.")
            return
        }
        let line = script[index]
        let text = "Next (\(index + 1)/\(script.count)): \(line.say)"
        overlay.show(prefix.isEmpty ? text : prefix + "\n" + text)
        print(text)
    }

    private func hotKey(_ id: UInt32, _ pressed: Bool) {
        switch (id, pressed) {
        case (Self.talkID, true):
            guard !recording, !busy else { return }
            recording = true
            listener.begin()
            overlay.show("● listening")
        case (Self.talkID, false):
            guard recording else { return }
            recording = false
            busy = true
            let t0 = Clock.nowNs()
            Task { await self.finish(t0: t0) }
        case (Self.markID, true):
            guard lastID > 0 else { return }
            log.write(["event": "mark_wrong", "ref": lastID])
            print("Marked #\(lastID) as wrong.")
            overlay.show("Marked #\(lastID) as wrong")
        case (Self.quitID, true):
            listener.stop()
            overlay.hide()
            let median = Stats.median(focusTimes)
            print("\nSession ended. \(count) commands. Median time to focused box: \(Stats.ms(median)).")
            print("Run: swift run earshot-probe report")
            exit(0)
        default:
            break
        }
    }

    private func finish(t0: UInt64) async {
        let watch = Stopwatch(t0: t0)
        var heard = ""
        do {
            heard = try await listener.end()
        } catch {
            print("Speech error: \(error)")
        }
        watch.mark("text")
        count += 1
        let id = count
        lastID = id
        let line: ScriptLine? = index < script.count ? script[index] : nil
        if index < script.count { index += 1 }

        var record: [String: Any] = ["event": "command", "id": id, "mode": "voice", "heard": heard]
        if let line { record["expected"] = line.say }

        guard let cmd = router.route(heard) else {
            record["route"] = "none"
            record["stages"] = watch.dictionary
            record["hearing"] = line?.scored == true ? "miss" : "unscored"
            log.write(record)
            print("#\(id) heard \"\(heard)\" → no command")
            busy = false
            showNext(prefix: "✗ \"\(heard)\" is not a command")
            return
        }
        watch.mark("route")
        let out = await pipeline.execute(cmd, watch: watch, typing: .selfOnly)

        var hearing = "unscored"
        if let line, line.scored {
            let samePerson = cmd.person?.name == line.personName
            hearing = (cmd.app.id == line.appID && samePerson) ? "ok" : "miss"
        }
        record["route"] = cmd.describe
        record["app"] = cmd.app.id
        record["person"] = cmd.person?.name ?? ""
        record["hearing"] = hearing
        record["stages"] = watch.dictionary
        record["outcome"] = out.dictionary
        log.write(record)

        if let f = watch.value("focus"), out.ok { focusTimes.append(f) }
        let total = watch.value("focus").map { "\(Int($0.rounded())) ms" } ?? "-"
        let mark = out.ok ? "✓" : "✗"
        print("#\(id) \(mark) heard \"\(heard)\" → \(cmd.describe) · \(watch.summary)\(out.reason.map { " · \($0)" } ?? "")")
        busy = false
        showNext(prefix: "\(mark) \(cmd.describe) · \(total)\(out.reason.map { " · \($0)" } ?? "")")
    }
}
