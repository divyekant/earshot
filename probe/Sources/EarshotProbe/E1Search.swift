import AppKit

// E1: the app's own search as the name source. The sidebar shows only some chats
// (Slack showed 3), but the app's search knows every chat. The probe types the name
// into the search, reads the result list, clears the field and presses Escape.
// It never presses Return, so it opens no chat (R-NV-5).

struct SearchRead {
    var results: [String] = []
    var failure: String?
    /// From the app in front to the name in the field.
    var typedMs = 0.0
    /// From the app in front to the last change of the result list.
    var resultsMs = 0.0
    var closed = false
}

extension Pipeline {
    func readSearch(row: AppRow, name: String) async -> SearchRead {
        var out = SearchRead()
        guard await bringToFront(bundleID: row.bundleID), let pid = running(row)?.processIdentifier else {
            out.failure = "\(row.name) did not come to the front"
            return out
        }
        let app = AX.appElement(pid)
        if row.electron == true { AX.set(app, "AXManualAccessibility", kCFBooleanTrue) }
        let t0 = Clock.nowNs()
        let (found, failure) = await typeIntoSwitcher(app: app, row: row, name: name)
        out.typedMs = Clock.ms(since: t0)
        guard let field = found else {
            out.failure = failure
            return out
        }
        // Read the list until it stops changing: 3 equal reads, 60 ms apart, 1.5 s at most.
        var last: [String] = []
        var lastChange = Clock.ms(since: t0)
        var stable = 0
        let t1 = Clock.nowNs()
        while Clock.ms(since: t1) < 1500 {
            await sleepMs(60)
            let now = Pipeline.resultTexts(app: app, field: field)
            if now == last {
                if !now.isEmpty { stable += 1 }
                if stable >= 2 { break }
            } else {
                stable = 0
                last = now
                lastChange = Clock.ms(since: t0)
            }
        }
        out.results = last
        out.resultsMs = lastChange
        // Clear the name, then close the search. Clear only while the focus is still in the search field.
        if let el = AX.focused(app), let win = AX.window(app), AX.isSwitcherField(el, in: win),
           !AX.isComposer(el, in: win) {
            Keys.press(Keys.selectAll)
            Keys.press(Keys.deleteKey)
        }
        Keys.press(Keys.escape)
        await sleepMs(150)
        if let el = AX.focused(app), let win = AX.window(app) {
            out.closed = !AX.isSwitcherField(el, in: win) || (AX.value(el) ?? "").isEmpty
        } else {
            out.closed = true
        }
        return out
    }

    /// Reads the result list: the names below the search field, in the same column.
    /// It skips the field itself, message boxes and live regions.
    static func resultTexts(app: AXUIElement, field: AXUIElement, budgetMs: Int = 200, maxNodes: Int = 5000) -> [String] {
        guard let ff = AX.frame(field), let win = AX.window(app), let w = AX.frame(win) else { return [] }
        let left = ff.x - 0.05 * w.w
        let right = ff.x + ff.w + 0.05 * w.w
        let bottom = ff.maxY + 0.6 * w.h
        var roots = AX.elements(app, "AXWindows")
        if roots.isEmpty { roots = [win] }
        let t0 = Clock.nowNs()
        var items: [(name: String, y: Double)] = []
        var seen = Set<String>()
        var count = 0
        func add(_ raw: String?, _ y: Double) -> Bool {
            guard let raw else { return false }
            // "Ravi Kumar, Active" gives "Ravi Kumar".
            let first = raw.split(separator: ",").first.map(String.init) ?? raw
            guard let c = NameIndex.clean(first) else { return false }
            if seen.insert(Text.key(c.name)).inserted { items.append((c.name, y)) }
            return true
        }
        for root in roots {
            var queue: [AXUIElement] = [root]
            var i = 0
            while i < queue.count, count < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
                let el = queue[i]
                i += 1
                count += 1
                if CFEqual(el, field) { continue }
                let r = AX.role(el)
                if ["AXMenuBar", "AXImage", "AXScrollBar", "AXToolbar", "AXTextArea"].contains(r) { continue }
                if NameIndex.liveRegions.contains(AX.subrole(el)) { continue }
                let frame = AX.frame(el)
                if let f = frame, f.w > 0, f.h > 0, !CFEqual(el, root) {
                    // Leave out what is above the field, beside it, or far below it (the message box).
                    if f.maxY <= ff.maxY || f.x > right || f.x + f.w < left || f.y > bottom { continue }
                }
                let visible = frame.map { $0.w > 0 && $0.h > 0 && $0.midY > ff.maxY } ?? false
                if r == "AXRow" || r == "AXCell" || r == "AXMenuItem" {
                    if visible, let f = frame {
                        for text in NameIndex.rowTexts(el) where add(text, f.midY) { break }
                    }
                    continue
                }
                if visible, let f = frame {
                    if r == "AXStaticText" {
                        let v = AX.string(el, "AXValue") ?? ""
                        _ = add(v.isEmpty ? AX.string(el, "AXDescription") : v, f.midY)
                    } else if r == "AXButton" || r == "AXLink" {
                        _ = add(AX.string(el, "AXTitle") ?? AX.string(el, "AXDescription"), f.midY)
                    }
                }
                queue.append(contentsOf: AX.elements(el, "AXChildren"))
            }
        }
        return items.sorted { $0.y < $1.y }.prefix(12).map(\.name)
    }
}

extension E1 {
    /// How well a result names the searched person: the full name, or the first name.
    static func nameScore(_ term: String, _ result: String) -> Double {
        let t = Text.key(term)
        let full = Text.key(result)
        var s = Text.similarity(t, full)
        if let first = Text.normalize(result).split(separator: " ").first {
            s = max(s, 0.95 * Text.similarity(t, String(first)))
        }
        return s
    }

    /// e1-search: types names into each chat app's own search and reads the results.
    /// It presses keys, but never Return. It opens no chat and types no message.
    static func search(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: true) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let cat = try Catalogue.load()
        let idx = try NameIndex.load()
        let set = try? loadCommands()
        let pos = Commands.positional(args)
        let perApp = Int(Commands.option(args, "--per-app") ?? "") ?? 10
        let extra = Commands.option(args, "--terms")?.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let apps = cat.apps.filter { a in
            a.chat && a.openChat != nil
                && (pos.isEmpty ? idx.entries.contains { $0.app == a.id && !$0.isSelf } : pos.contains(a.id))
        }
        let rows = apps.compactMap { $0.appRow() }
        let pipeline = Pipeline(apps: rows)
        pipeline.prime()
        let before = NSWorkspace.shared.frontmostApplication
        defer { before?.activate() }
        let log = try RunLog(kind: "search", experiment: "e1")
        let people = (try? Config.loadPeople())?.filter { !$0.me }.map(\.name) ?? []
        print("E1: names typed into each app's own search. No Return, no chat opens. Do not touch the keyboard or mouse.")
        print("Log: \(log.url.path)\n")

        var summary: [String] = []
        for row in rows {
            var terms: [String] = []
            func addTerm(_ t: String) {
                let k = Text.key(t)
                if !k.isEmpty, !terms.contains(where: { Text.key($0) == k }) { terms.append(t) }
            }
            extra.forEach(addTerm)
            people.forEach(addTerm)
            // Names from the test commands for this app.
            for c in set?.commands ?? [] {
                for e in c.expected where e.action == "open_chat" && e.app == row.id {
                    if let t = e.target, !(idx.entries.first(where: { $0.app == row.id && $0.name == t })?.isSelf ?? false) {
                        addTerm(firstName(t))
                    }
                }
            }
            // Names that another app shows. The sidebar of this app may hide them.
            for e in idx.entries where e.app != row.id && !e.isSelf { addTerm(firstName(e.name)) }
            terms = Array(terms.prefix(perApp))
            if let first = terms.first { terms.append(mishear(first)) }
            terms.append(idx.owner)
            terms.append(unknownNames[0])

            var found = 0, top = 0
            var times: [Double] = []
            for term in terms {
                let r = await pipeline.readSearch(row: row, name: term)
                let scored = r.results.enumerated().map { ($0.offset, $0.element, nameScore(term, $0.element)) }
                let best = scored.max { $0.2 < $1.2 }
                let match = best.map { $0.2 >= 0.8 } ?? false
                if match { found += 1 }
                if match, best?.0 == 0 { top += 1 }
                if r.failure == nil { times.append(r.resultsMs) }
                var line = "\(row.name) \"\(term)\": "
                if let f = r.failure {
                    line += "FAILED: \(f)"
                } else {
                    line += "\(r.results.count) results in \(Int(r.resultsMs.rounded())) ms"
                    if let b = best, match { line += ", match \"\(b.1)\" at place \(b.0 + 1)" } else { line += ", no match" }
                    line += ": \(r.results.prefix(6).joined(separator: " | "))"
                    if !r.closed { line += " · SEARCH STILL OPEN" }
                }
                print(line)
                var entry: [String: Any] = ["event": "search", "app": row.id, "term": term, "results": r.results,
                                            "typed_ms": r.typedMs, "results_ms": r.resultsMs, "match": match,
                                            "closed": r.closed]
                if let b = best { entry["best"] = b.1; entry["best_place"] = b.0 + 1; entry["best_score"] = b.2 }
                if let f = r.failure { entry["failure"] = f }
                log.write(entry)
                await sleepMs(400)
            }
            summary.append("\(row.name): a matching chat for \(found) of \(terms.count) names (top result for \(top)); "
                           + "results after median \(Stats.ms(Stats.median(times))), slowest 1 in 10 \(Stats.ms(Stats.percentile(times, 0.9)))")
        }
        print("\nSummary")
        summary.forEach { print("  " + $0) }
        print("  The last two names of each app are your own name and a name that is not in your chats.")
        return 0
    }
}
