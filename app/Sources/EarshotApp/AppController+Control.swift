import AppKit
import EarshotCore
import Foundation

// The requests of the command line (R-CT-1 to R-CT-4, docs/CONTROL.md). In its own file, so that AppController
// changes by a few lines only.

extension AppController {
    /// Opens the control socket. An error goes to the system log only: earshot works without the command line.
    func startControl() {
        let server = ControlServer(path: ControlServer.path(store)) { [weak self] request, peerIsEarshot in
            guard let self else { return ControlReply(ok: false, lines: ["earshot is closing."]) }
            return await self.handleControl(request, peerIsEarshot: peerIsEarshot)
        }
        do { try server.start() } catch { NSLog("earshot: control socket: \(error)") }
        control = server
    }

    func handleControl(_ request: ControlRequest, peerIsEarshot: Bool) async -> ControlReply {
        switch request.cmd {
        case "status":
            return ControlReply(ok: true, lines: statusLines())
        case "reload":
            reloadFromDisk()
            return ControlReply(ok: true, lines: ["earshot read settings.json and the plugins folder again."])
        case "restart-plugin":
            guard let id = request.plugin, !id.isEmpty else { return ControlReply(ok: false, lines: ["no plugin id"]) }
            if let why = plugins.restart(id) { return ControlReply(ok: false, lines: ["Not restarted: \(why)."]) }
            return ControlReply(ok: true, lines: ["The plugin \(id) runs again."])
        case "run":
            return await runControl(request, peerIsEarshot: peerIsEarshot)
        default:
            return ControlReply(ok: false, lines: ["unknown request \"\(request.cmd)\""])
        }
    }

    /// Reads settings.json and the plugins again, as after a change in the Manage window.
    func reloadFromDisk() {
        apply(store.settings)
        refreshListen()
        plugins.reload()
    }

    private func statusLines() -> [String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let commit = info["EarshotCommit"] as? String ?? "?"
        let running = plugins.runningIDs
        return [
            "earshot \(version) (\(commit.prefix(7)))",
            "mode: \(settings.mode.rawValue), \(listenLabel)",
            "state: \(status)",
            "plugins running: " + (running.isEmpty ? "none" : running.joined(separator: ", ")),
        ]
    }

    /// A typed command, as the Test tab runs it (R-CT-4). With actions, it can click and type as a spoken command
    /// does, with the same safety rules: no Send without the word "send" (R-NV-5).
    private func runControl(_ request: ControlRequest, peerIsEarshot: Bool) async -> ControlReply {
        guard let text = request.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return ControlReply(ok: false, lines: ["no words"])
        }
        let actions = request.actions ?? false
        if actions, !peerIsEarshot {
            return ControlReply(ok: false, lines: ["run --actions works only from the earshot command line."])
        }
        control?.startCollecting()
        let report = await pipeline.test(text, runActions: actions)
        var lines = [
            "heard: \(report.heard)",
            "intent: \(report.route.intent)",
            "tier: \(report.route.tier), confidence \((report.route.confidence * 100).rounded() / 100), "
                + "\((report.route.ms * 10).rounded() / 10) ms, \(report.route.why)",
        ]
        var ok = true
        if let outcome = report.outcome {
            ok = outcome.ok
            lines.append((outcome.ok ? "done: " : "failed: ") + outcome.note)
            if case .handOff(_, _, _) = report.route.intent, outcome.ok {
                // The answer of a plugin comes later. Wait for the first answer, then a short time for more.
                let wait = request.wait ?? 3
                let start = Date()
                while (control?.collectedCount ?? 0) == 0, Date().timeIntervalSince(start) < wait {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                if (control?.collectedCount ?? 0) > 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
            }
        } else {
            lines.append(actions ? "no action: the confidence is too low or there is no intent" : "dry run: no action")
        }
        let answers = control?.stopCollecting() ?? []
        lines += answers.map { "answer: \($0)" }
        return ControlReply(ok: ok, lines: lines)
    }
}
