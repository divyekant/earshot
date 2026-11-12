import Foundation

/// The local pages (build spec 11.1): today.html, all-open.html and one page for each open project. Each file is
/// complete in itself: inline style, no script, no image, no font and no network address in the page code.
extension Engine {
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }

    static let pageStyle = """
    :root{color-scheme:dark light;--bg:#000;--fg:#fff;--dim:#9a9a9a;--line:#262626;--late:#ff8a7a}
    @media (prefers-color-scheme: light){:root{--bg:#fff;--fg:#111;--dim:#666;--line:#e3e3e3;--late:#b3261e}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--fg);font:18px/1.5 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    main{max-width:760px;margin:0 auto;padding:48px 20px 80px}
    h1{font-size:40px;font-weight:600;letter-spacing:-0.02em;margin:0 0 4px}
    .sub{color:var(--dim);margin:0 0 40px}
    h2{font-size:14px;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--dim);margin:40px 0 8px}
    ul{list-style:none;margin:0;padding:0}
    li{padding:12px 0;border-bottom:1px solid var(--line);display:flex;gap:16px;justify-content:space-between}
    li .when{color:var(--dim);white-space:nowrap}
    li.late .when{color:var(--late)}
    .empty{color:var(--dim)}
    nav a,li a{color:var(--fg)}
    nav{margin-top:56px;color:var(--dim);font-size:15px}
    table{border-collapse:collapse;width:100%}
    td{padding:8px 0;border-bottom:1px solid var(--line)}
    td.n{text-align:right;font-variant-numeric:tabular-nums}
    """

    func page(title: String, sub: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(Engine.escape(title)) · PA</title><style>\(Engine.pageStyle)</style></head>
        <body><main><h1>\(Engine.escape(title))</h1><p class="sub">\(Engine.escape(sub))</p>
        \(body)
        <nav><a href="today.html">Today</a> · <a href="all-open.html">All open</a> · <a href="flags.html">Flags</a></nav>
        </main></body></html>
        """
    }

    func section(_ title: String, _ items: [Item], late: Bool = false, empty: String? = nil) -> String {
        if items.isEmpty {
            guard let empty else { return "" }
            return "<h2>\(Engine.escape(title))</h2><p class=\"empty\">\(Engine.escape(empty))</p>"
        }
        let lis = items.map { it -> String in
            var label = it.title.isEmpty ? it.said : it.title
            if let p = projectLabel(it) { label += " · " + p }
            let when = shortTime(it).map { "<span class=\"when\">\(Engine.escape($0))</span>" } ?? ""
            return "<li\(late ? " class=\"late\"" : "")><span>\(Engine.escape(label))</span>\(when)</li>"
        }.joined()
        return "<h2>\(Engine.escape(title))</h2><ul>\(lis)</ul>"
    }

    func docSection(_ docs: [Doc]) -> String {
        guard !docs.isEmpty else { return "" }
        let lis = docs.map { d -> String in
            var link = Engine.escape(d.title)
            // A kept web address or file path is shown as a normal link that the owner can click. The page does not
            // load it.
            if let a = d.address, a.hasPrefix("http://") || a.hasPrefix("https://") || a.hasPrefix("/") {
                let href = a.hasPrefix("/") ? "file://" + a : a
                link = "<a href=\"\(Engine.escape(href))\">\(link)</a>"
            } else if let path = d.path {
                link = "<a href=\"\(Engine.escape(URL(fileURLWithPath: path).absoluteString))\">\(link)</a>"
            }
            if d.textState == .gone { link += " (file moved or deleted)" }
            if d.kind == .folder, let store {
                let n = store.docs(where: "dropped_at IS NULL AND parent_doc_id = ?", [.int(d.id)]).count
                link += " · folder, \(n) file\(n == 1 ? "" : "s")"
            }
            return "<li><span>\(link)</span></li>"
        }.joined()
        return "<h2>Documents</h2><ul>\(lis)</ul>"
    }

    /// The pages need a new write. The PA writes them at most one time each second.
    func markPagesDirty() { pagesDirty = true }

    /// Writes the pages if they need it and the last write is 1 s ago or more.
    public func flushPages(force: Bool = false) {
        guard pagesDirty || force, store != nil else { return }
        let now = clock.now
        if !force, let last = pagesWrittenAt, now.timeIntervalSince(last) < 1 { return }
        pagesDirty = false
        pagesWrittenAt = now
        writePages()
    }

    func writePages() {
        guard let store else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        let cal = clock.calendar
        let now = clock.now
        let today = Day(now, cal)
        let tomorrow = today.adding(days: 1, cal)
        let open = store.items(where: "state = 'open'")
        func day(_ it: Item) -> Day? { it.remindAt.map { Day($0, cal) } ?? it.dueOn }
        func when(_ it: Item) -> Date { it.remindAt ?? it.dueOn?.date(cal) ?? it.createdAt }
        let tasks = open.filter { $0.kind != .note }
        let late = tasks.filter { day($0).map { $0 < today } ?? false }.sorted { when($0) < when($1) }
        let todayItems = tasks.filter { day($0) == today }.sorted { when($0) < when($1) }
        let tomorrowItems = tasks.filter { day($0) == tomorrow }.sorted { when($0) < when($1) }
        let quietIDs = Set(morningItems(now).map(\.id)).subtracting((late + todayItems + tomorrowItems).map(\.id))
        let quiet = tasks.filter { quietIDs.contains($0.id) }
        let counts = store.eventCounts(since: now.addingTimeInterval(-7 * 86400))
        var rows: [(String, Int)] = [
            ("Captures", counts["capture", default: 0] + counts["keep", default: 0]),
            ("Done", counts["done", default: 0]),
            ("Snoozed", counts["snooze", default: 0]),
            ("Dropped", counts["drop", default: 0]),
            ("Alerts shown", counts["alert-shown", default: 0] + counts["alert-repeat", default: 0]),
            ("Alerts with no answer", counts["alert-no-answer", default: 0]),
            ("Project proposals", counts["proposal", default: 0]),
            ("Project proposals corrected", counts["proposal-corrected", default: 0]),
        ]
        let nearEvent = store.eventAlertAnswers(since: now.addingTimeInterval(-7 * 86400))
        rows += [("Near-event alerts", nearEvent.shown), ("Near-event alerts with an answer", nearEvent.answered)]
        rows += [("Flags", counts["flag", default: 0]), ("Flags kept", counts["flag-keep", default: 0]),
                 ("Flags dropped", counts["flag-drop", default: 0])]
        let table = "<h2>The last 7 days</h2><table>" + rows.map { "<tr><td>\($0.0)</td><td class=\"n\">\($0.1)</td></tr>" }.joined() + "</table>"
        // 8.1, step 6: the PA does not change the setting by itself.
        var warning = ""
        let made = counts["proposal", default: 0], corrected = counts["proposal-corrected", default: 0]
        if made >= 10, Double(corrected) / Double(made) > 0.2 {
            warning = "<p class=\"empty\">Many project proposals were wrong. Set proposeProject to false in the settings to stop them.</p>"
        }
        // The senders with no more request flags (8.8, "3 drops and no keep").
        var muted = ""
        if !settings.flagsMuted.isEmpty {
            muted = "<h2>No more flags from</h2><ul>" + settings.flagsMuted.map { a in
                "<li><span>\(Engine.escape(store.senderName(a) ?? a))</span></li>" }.joined()
                + "</ul><p class=\"empty\">To get flags from a sender again, delete the line in flagsMuted in the settings.</p>"
        }
        let todayBody = warning + section("Late", late, late: true) + section("Today", todayItems, empty: "Nothing for today.")
            + section("Tomorrow", tomorrowItems) + section("Quiet", quiet) + table + muted
        let dateLine = TimeText.fullDay(today, cal)
        write(page(title: "Today", sub: dateLine, body: todayBody), "today.html")

        // All open: by project, then the items with no project.
        var allBody = ""
        let projects = store.projects()
        for p in projects {
            let items = tasks.filter { $0.projectID == p.id }.sorted { when($0) < when($1) }
            allBody += section(p.name, items)
        }
        allBody += section("No project", tasks.filter { $0.projectID == nil }.sorted { when($0) < when($1) },
                           empty: projects.isEmpty ? "Nothing open." : nil)
        write(page(title: "All open", sub: "\(tasks.count) open", body: allBody), "all-open.html")

        // The open flags (8.6), with a link that opens the mail.
        let flags = store.openFlags()
        var flagsBody = flags.isEmpty ? "<p class=\"empty\">Nothing new.</p>" : "<ul>"
        for f in flags {
            let text = Engine.escape(flagLine(f))
            let subject = f.subject.isEmpty ? "" : "<br><span class=\"when\">\(Engine.escape(f.subject))</span>"
            let link = f.mailLink.map { "<a href=\"\(Engine.escape($0))\">Open</a>" } ?? ""
            flagsBody += "<li><span>\(text)\(subject)</span><span class=\"when\">\(link)</span></li>"
        }
        if !flags.isEmpty { flagsBody += "</ul>" }
        flagsBody += "<p class=\"empty\">The PA finds about half of the requests. Do not use it as your only check of the inbox.</p>"
        write(page(title: "Flags", sub: "\(flags.count) open", body: flagsBody), "flags.html")

        // One page for each open project.
        let since = now.addingTimeInterval(-30 * 86400).timeIntervalSince1970
        var keep: Set<String> = ["today.html", "all-open.html", "search.html", "main-points.html", "flags.html"]
        // The page of a closed project stays in the folder (phase 2 build spec 7.5).
        for p in store.projects(openOnly: false) where p.state == "closed" { keep.insert("project-\(p.slug).html") }
        for p in projects {
            let items = tasks.filter { $0.projectID == p.id }.sorted { when($0) < when($1) }
            let done = store.items(where: "state = 'done' AND project_id = ? AND done_at >= ?", [.int(p.id), .real(since)],
                                   order: "done_at DESC")
            let notes = open.filter { $0.kind == .note && $0.projectID == p.id }
            // The files of a kept folder are not listed one by one: the folder line gives the count.
            let docs = store.docs(project: p.id).filter { $0.parentDocID == nil }
            let new = arrivals(since: now.addingTimeInterval(-7 * 86400), project: p.id)
            let newSection = new.isEmpty ? "" : "<h2>New</h2><ul>" + new.reversed().map {
                "<li><span>\(Engine.escape(arrivalText($0)))</span></li>" }.joined() + "</ul>"
            let body = section("Open", items, empty: "Nothing open.") + newSection + docSection(docs)
                + section("Notes", notes) + section("Done in the last 30 days", done)
            let name = "project-\(p.slug).html"
            keep.insert(name)
            write(page(title: p.name, sub: "Project", body: body), name)
        }
        // Remove the pages of projects that are gone.
        for f in (try? fm.contentsOfDirectory(atPath: pagesFolder.path)) ?? [] where f.hasSuffix(".html") && !keep.contains(f) {
            try? fm.removeItem(at: pagesFolder.appendingPathComponent(f))
        }
    }

    func write(_ html: String, _ name: String) {
        try? Data(html.utf8).write(to: pagesFolder.appendingPathComponent(name), options: .atomic)
    }

    // MARK: - Targets (build spec 11.2)

    public func targets() -> [Target] {
        var out = [
            Target(id: "page-today", name: "today", kind: "page", open: pagesFolder.appendingPathComponent("today.html").path),
            Target(id: "page-all-open", name: "all open", kind: "page", open: pagesFolder.appendingPathComponent("all-open.html").path),
            Target(id: "page-flags", name: "flags", kind: "page", open: pagesFolder.appendingPathComponent("flags.html").path),
        ]
        // "open search" shows the full results of the last search (phase 2 build spec, 7.7).
        if FileManager.default.fileExists(atPath: searchPageURL.path) {
            out.append(Target(id: "page-search", name: "search", kind: "page", open: searchPageURL.path))
        }
        if FileManager.default.fileExists(atPath: mainPointsPageURL.path) {
            out.append(Target(id: "page-main-points", name: "main points", kind: "page", open: mainPointsPageURL.path))
        }
        for p in store?.projects() ?? [] {
            out.append(Target(id: "project-\(p.id)", name: p.name, kind: "project",
                              open: pagesFolder.appendingPathComponent("project-\(p.slug).html").path))
        }
        return out
    }

    func sendTargets() {
        output.send(.targets(targets()))
    }
}
