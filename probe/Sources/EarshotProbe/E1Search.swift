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
        // A search that an earlier step left open would stop the focus check. Close it first.
        if searchOpen(app) { _ = await closeSearch(app) }
        let t0 = Clock.nowNs()
        let (found, failure) = await typeIntoSwitcher(app: app, row: row, name: name)
        out.typedMs = Clock.ms(since: t0)
        guard let field = found else {
            out.failure = failure
            // A failed search can stay open with the focus on one of its buttons. Escape closes it.
            // Escape never sends a message.
            Keys.press(Keys.escape)
            await sleepMs(150)
            out.closed = await closeSearch(app)
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
        // Messages needs a second Escape: the first closes the suggestions, the second the new message.
        out.closed = await closeSearch(app, field: field)
        return out
    }

    /// True if a search field has the focus: a switcher field that is not a message box.
    func searchOpen(_ app: AXUIElement) -> Bool {
        guard let el = AX.focused(app), let win = AX.window(app) else { return false }
        return AX.isSwitcherField(el, in: win) && !AX.isComposer(el, in: win)
    }

    /// Presses Escape while a search field has the focus, or while the field that the probe
    /// typed into is still on screen, 3 times at most. Returns true if the search closed.
    func closeSearch(_ app: AXUIElement, field: AXUIElement? = nil) async -> Bool {
        func open() -> Bool {
            if searchOpen(app) { return true }
            guard let field, let f = AX.frame(field) else { return false }
            return f.w > 0 && f.h > 0
        }
        for _ in 0..<3 {
            if !open() { return true }
            Keys.press(Keys.escape)
            await sleepMs(200)
        }
        return !open()
    }

    /// Reads the result list: the names below the search field, in the same column.
    /// It joins the texts of one screen line into one result ("Darshan" + "Pania"), because one
    /// result row can hold several texts. It drops prompt lines such as "Search for: ravi",
    /// file names and section titles. It skips the field itself, message boxes, live regions,
    /// and everything to the left of the field (the sidebar).
    static func resultTexts(app: AXUIElement, field: AXUIElement, budgetMs: Int = 200, maxNodes: Int = 5000) -> [String] {
        guard let ff = AX.frame(field), let win = AX.window(app), let w = AX.frame(win) else { return [] }
        let right = ff.x + ff.w + 0.05 * w.w
        let bottom = ff.maxY + 0.6 * w.h
        var roots = AX.elements(app, "AXWindows")
        if roots.isEmpty { roots = [win] }
        let t0 = Clock.nowNs()
        var pieces: [(text: String, f: Frame)] = []
        var count = 0
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
                    // Leave out what is above the field, to its left (the sidebar), to its right,
                    // or far below it (the message box).
                    if f.maxY <= ff.maxY || f.x + f.w < ff.x - 4 || f.x > right || f.y > bottom { continue }
                }
                if let f = frame, f.w > 0, f.h > 0, f.midY > ff.maxY, f.midX >= ff.x - 0.03 * w.w, f.midX <= right {
                    var text: String?
                    if r == "AXStaticText" {
                        let v = AX.string(el, "AXValue") ?? ""
                        text = v.isEmpty ? AX.string(el, "AXDescription") : v
                    } else if r == "AXButton" || r == "AXLink" || r == "AXMenuItem" {
                        text = AX.string(el, "AXTitle") ?? AX.string(el, "AXDescription")
                    }
                    if let t = text.map(Text.squash), !t.isEmpty { pieces.append((t, f)) }
                }
                queue.append(contentsOf: AX.elements(el, "AXChildren"))
            }
        }

        // Group the pieces into screen lines, then join each line from left to right.
        let sorted = pieces.sorted { $0.f.midY < $1.f.midY }
        var lines: [[(text: String, f: Frame)]] = []
        for p in sorted {
            if let last = lines.last?.last, abs(p.f.midY - last.f.midY) <= max(6, 0.5 * min(p.f.h, last.f.h)) {
                lines[lines.count - 1].append(p)
            } else {
                lines.append([p])
            }
        }
        var out: [String] = []
        var seen = Set<String>()
        for line in lines {
            var words: [String] = []
            for p in line.sorted(by: { $0.f.x < $1.f.x }) where words.last != p.text { words.append(p.text) }
            let joined = words.joined(separator: " ")
            let lower = joined.lowercased()
            // Prompt lines repeat the typed text: "Show results for: ravi", "Search for: ravi".
            if promptStarts.contains(where: { lower.hasPrefix($0) }) { continue }
            // File names, links and section titles in capital letters ("SIRI FOUND IN APPS").
            if lower.range(of: #"\.[a-z0-9]{2,5}$"#, options: .regularExpression) != nil || lower.contains("://") { continue }
            let parts = joined.split(separator: " ")
            if parts.count >= 3, !joined.contains(where: \.isLowercase) { continue }
            let first = joined.split(separator: ",").first.map(String.init) ?? joined
            guard let c = NameIndex.clean(first), seen.insert(Text.key(c.name)).inserted else { continue }
            out.append(c.name)
            if out.count >= 12 { break }
        }
        return out
    }

    static let promptStarts = ["show results for", "search for", "results for", "recent messages", "no results",
                               "try searching", "search all", "jump to"]
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
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let log = try RunLog(kind: "search", experiment: "e1")
        let people = (try? Config.loadPeople())?.filter { !$0.me }.map(\.name) ?? []
        print("E1: names typed into each app's own search. No Return, no chat opens. Do not touch the keyboard or mouse.")
        print("Log: \(log.url.path)\n")

        var summary: [String] = []
        var stopped = false
        for row in rows where !stopped {
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
            var failures = 0
            for term in terms {
                let r = await pipeline.readSearch(row: row, name: term)
                if r.failure != nil { failures += 1 } else { failures = 0 }
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
                // SAFETY: stop at once if a search stays open, or after 2 failures in a row.
                if !r.closed {
                    print("STOP: the search did not close in \(row.name). Check the app.")
                    stopped = true
                    break
                }
                if failures >= 2 {
                    print("STOP: 2 failures in a row in \(row.name). The probe leaves this app.")
                    break
                }
                await sleepMs(400)
            }
            summary.append("\(row.name): a matching chat for \(found) of \(terms.count) names (top result for \(top)); "
                           + "results after median \(Stats.ms(Stats.median(times))), slowest 1 in 10 \(Stats.ms(Stats.percentile(times, 0.9)))")
        }
        // Bring back the app that was in front before the run.
        if let id = before { _ = await pipeline.bringToFront(bundleID: id) }
        print("\nSummary")
        summary.forEach { print("  " + $0) }
        if stopped { print("  The run STOPPED early. See the STOP line above.") }
        print("  The last two names of each app are your own name and a name that is not in your chats.")
        return 0
    }
}
