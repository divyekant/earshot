import Foundation

/// Reads a JSONL log and prints the E0 checks per app.
enum Report {
    static func newestLog() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    static func run(_ path: String?) throws -> Int32 {
        guard let url = path.map({ URL(fileURLWithPath: $0) }) ?? newestLog() else {
            throw ProbeError("no log in probe/logs/")
        }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        var commands: [[String: Any]] = []
        var wrong: Set<Int> = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch obj["event"] as? String {
            case "command": commands.append(obj)
            case "mark_wrong": if let ref = obj["ref"] as? Int { wrong.insert(ref) }
            default: break
            }
        }

        print("Report for \(url.lastPathComponent): \(commands.count) commands, \(wrong.count) marked wrong\n")
        print(pad("App", 10) + pad("Runs", 6) + pad("Reach", 10) + pad("Verified", 10) + pad("Median", 10)
              + pad("Slowest 1/10", 14) + pad("Speech", 10) + pad("Hearing", 9) + "Typed")
        let apps = Array(Set(commands.compactMap { $0["app"] as? String })).sorted()
        var allFocus: [Double] = []
        for app in apps + ["all"] {
            let rows = app == "all" ? commands.filter { $0["app"] != nil } : commands.filter { ($0["app"] as? String) == app }
            guard !rows.isEmpty else { continue }
            var reach = 0, verified = 0, typed = 0, hearOK = 0, hearScored = 0
            var focus: [Double] = [], speech: [Double] = []
            for r in rows {
                let id = r["id"] as? Int ?? -1
                let out = r["outcome"] as? [String: Any] ?? [:]
                let stages = r["stages"] as? [String: Any] ?? [:]
                let ok = (out["ok"] as? Bool ?? false) && !wrong.contains(id)
                if ok { reach += 1 }
                let check = out["chat_check"] as? String ?? ""
                if ok && (check == "title" || check == "header") { verified += 1 }
                if out["typed"] as? Bool == true { typed += 1 }
                if ok, let f = (stages["focus"] as? NSNumber)?.doubleValue {
                    // Count speed only when the app was already open (see the plan).
                    if out["warm"] as? Bool ?? true { focus.append(f) }
                }
                if let s = (stages["text"] as? NSNumber)?.doubleValue { speech.append(s) }
                if let h = r["hearing"] as? String, h != "unscored" {
                    hearScored += 1
                    if h == "ok" { hearOK += 1 }
                }
            }
            if app == "all" { allFocus = focus }
            print(pad(app, 10) + pad("\(rows.count)", 6) + pad("\(reach)/\(rows.count)", 10)
                  + pad("\(verified)", 10) + pad(Stats.ms(Stats.median(focus)), 10)
                  + pad(Stats.ms(Stats.percentile(focus, 0.9)), 14) + pad(Stats.ms(Stats.median(speech)), 10)
                  + pad(hearScored == 0 ? "-" : "\(hearOK)/\(hearScored)", 9) + "\(typed)")
        }
        if let m = Stats.median(allFocus) {
            print("\nSpeed check: median \(Int(m.rounded())) ms from start (voice: key release) to focused box. Go needs under 1000 ms.")
        }
        print("Reach counts a command as wrong if you marked it. Verified = the chat name was found on screen.")
        return 0
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count)
    }
}
