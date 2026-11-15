import Foundation

/// The lists of Footnote as data, in pages/board.json (earshot docs/PLUGINS.md 5.5). earshot draws them in its window
/// and its panel with its own type and rows, so that Footnote looks like a part of earshot. The HTML pages stay for
/// the browser. The file holds text only: earshot never runs it as a command.
struct BoardFile: Codable, Equatable {
    var version = 1
    var panel: PanelList?
    var tabs: [Tab]
    var settingsTab: String?

    struct PanelList: Codable, Equatable {
        var title: String
        var rows: [Row]
        var empty: String?
    }

    struct Tab: Codable, Equatable {
        var id: String
        var title: String
        var heading: String?
        var sub: String?
        var date: String?
        var sections: [Section]
        var hint: String?
    }

    struct Section: Codable, Equatable {
        var title: String?
        var tone: String?
        var rows: [Row]?
        var numbers: [Number]?
        var text: String?
        var empty: String?
    }

    struct Row: Codable, Equatable {
        var text: String
        var detail: String?
        var when: String?
        var late: Bool?
        var mark: String?
        var open: String?
    }

    struct Number: Codable, Equatable {
        var label: String
        var value: Int
    }

    /// The limits of earshot: more rows are cut there. Footnote keeps under them.
    static let maxRows = 200
    static let panelRows = 6
}

extension Engine {
    static let boardName = "board.json"

    /// One to-do, reminder or note as a row.
    func boardRow(_ it: Item, late: Bool = false) -> BoardFile.Row {
        BoardFile.Row(text: it.title.isEmpty ? it.said : it.title, detail: projectLabel(it), when: shortTime(it),
                      late: late ? true : nil, mark: it.kind == .note ? "note" : "todo")
    }

    /// "1 late, 1 for today, 2 for tomorrow", or "Nothing late and nothing for today".
    static func todayLine(late: Int, today: Int, tomorrow: Int) -> String {
        var parts: [String] = []
        if late > 0 { parts.append("\(late) late") }
        if today > 0 { parts.append("\(today) for today") }
        if tomorrow > 0 { parts.append("\(tomorrow) for tomorrow") }
        return parts.isEmpty ? "Nothing late and nothing for today" : parts.joined(separator: ", ")
    }

    /// Writes pages/board.json from the lists that `writePages` made.
    func writeBoard(late: [Item], today: [Item], tomorrow: [Item], quiet: [Item], tasks: [Item], open: [Item],
                    projects: [Project], flags: [Flag], counts: [String: Int], dayText: String) {
        guard let store else { return }
        func rows(_ items: [Item], late: Bool = false) -> [BoardFile.Row] {
            Array(items.prefix(BoardFile.maxRows)).map { boardRow($0, late: late) }
        }
        func section(_ title: String, _ items: [Item], late: Bool = false, empty: String? = nil) -> BoardFile.Section? {
            if items.isEmpty && empty == nil { return nil }
            return BoardFile.Section(title: title, tone: late ? "late" : nil, rows: rows(items, late: late), empty: empty)
        }

        let numbers = BoardFile.Section(title: "The last 7 days", numbers: [
            BoardFile.Number(label: "captured", value: counts["capture", default: 0] + counts["keep", default: 0]),
            BoardFile.Number(label: "done", value: counts["done", default: 0]),
            BoardFile.Number(label: "snoozed", value: counts["snooze", default: 0]),
            BoardFile.Number(label: "dropped", value: counts["drop", default: 0]),
            BoardFile.Number(label: "alerts with no answer", value: counts["alert-no-answer", default: 0]),
            BoardFile.Number(label: "flags", value: counts["flag", default: 0]),
        ])
        let todayTab = BoardFile.Tab(
            id: "today", title: "Today",
            sub: Self.todayLine(late: late.count, today: today.count, tomorrow: tomorrow.count), date: dayText,
            sections: [section("Late", late, late: true), section("Today", today, empty: "Nothing for today."),
                       section("Tomorrow", tomorrow), section("Quiet", quiet), numbers].compactMap { $0 },
            hint: "Say “done” or “snooze” with the words of a to-do. Footnote keeps the list; earshot draws it.")

        var allSections: [BoardFile.Section] = []
        for p in projects {
            if let s = section(p.name, tasks.filter { $0.projectID == p.id }) { allSections.append(s) }
        }
        let loose = tasks.filter { $0.projectID == nil }
        if let s = section("No project", loose, empty: projects.isEmpty ? "Nothing open." : nil) { allSections.append(s) }
        let allTab = BoardFile.Tab(id: "all", title: "All open", sub: "\(tasks.count) open", sections: allSections)

        let flagRows = Array(flags.prefix(BoardFile.maxRows)).map { f in
            BoardFile.Row(text: flagLine(f), detail: f.subject.isEmpty ? nil : f.subject, mark: "flag", open: f.mailLink)
        }
        let flagsTab = BoardFile.Tab(id: "flags", title: "Flags", sub: "\(flags.count) open", sections: [
            BoardFile.Section(rows: flagRows, empty: "Nothing new."),
            BoardFile.Section(text: "Footnote finds about half of the requests. Do not use it as your only check of the inbox."),
        ])

        let projectRows = projects.map { p in
            let n = tasks.filter { $0.projectID == p.id }.count
            return BoardFile.Row(text: p.name, detail: "\(n) open", mark: "doc", open: "project-\(p.slug).html")
        }
        let projectsTab = BoardFile.Tab(id: "projects", title: "Projects", sub: "\(projects.count) open", sections: [
            BoardFile.Section(rows: projectRows, empty: "No projects. Say “new project” and a name."),
        ], hint: "A project opens as a page in your browser.")

        let kept = store.docs(where: "dropped_at IS NULL AND kind = 'page' AND address IS NOT NULL")
            .sorted { ($0.textAt ?? $0.createdAt) > ($1.textAt ?? $1.createdAt) }
            .prefix(BoardFile.maxRows)
        let keptRows = kept.map { d in
            var info: [String] = []
            if let site = Engine.siteName(d.address) { info.append(site) }
            info.append(keptCopyPath(d) != nil ? Engine.groupNumber(d.textWords ?? 0) + " words" : "no text")
            return BoardFile.Row(text: d.title, detail: info.joined(separator: " · "), mark: "doc",
                                 open: Engine.isWebAddress(d.address) ? d.address : nil)
        }
        let keptTab = BoardFile.Tab(id: "kept", title: "Kept", sub: "\(kept.count) page\(kept.count == 1 ? "" : "s")", sections: [
            BoardFile.Section(rows: keptRows, empty: "No kept pages. Say “keep this” on a web page."),
        ])

        let panelRows = (rows(late, late: true) + rows(today)).prefix(BoardFile.panelRows)
        let board = BoardFile(panel: BoardFile.PanelList(title: "Today", rows: Array(panelRows), empty: "Nothing for today."),
                              tabs: [todayTab, allTab, flagsTab, projectsTab, keptTab], settingsTab: "Rules")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(board) else { return }
        try? data.write(to: pagesFolder.appendingPathComponent(Self.boardName), options: .atomic)
    }

    /// "Sat 14 Nov": the short day at the top right of the board.
    static func boardDay(_ d: Day, _ cal: Calendar) -> String {
        "\(TimeText.weekdays[d.weekday(cal) - 1]) \(d.day) \(TimeText.months[d.month - 1])"
    }
}
