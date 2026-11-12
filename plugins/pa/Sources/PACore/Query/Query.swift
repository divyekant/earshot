import Foundation

/// Lists and search (build spec 9.5). Each list keeps its records in `last_list`, so "done 2" works.
extension Engine {
    /// The most lines of a list on screen (docs/PLUGINS.md).
    static let maxListLines = 10

    /// One line of a list: the title, then the time or the date if there is one.
    func line(_ it: Item) -> String {
        let title = it.title.isEmpty ? it.said : it.title
        guard let t = shortTime(it) else { return title }
        return title + " · " + t
    }

    /// The time of a list line: "17:00" today, else "Fri", "Fri 09:00", "Fri 13 Nov".
    func shortTime(_ it: Item) -> String? {
        let cal = clock.calendar
        let now = clock.now
        let today = Day(now, cal)
        if let at = it.remindAt, it.kind != .todo || it.hasClock {
            let d = Day(at, cal)
            let c = TimeText.clock(at, cal, locale: clock.locale)
            if d == today { return c }
            return TimeText.day(d, now: now, cal) + " " + c
        }
        if let d = it.dueOn { return TimeText.day(d, now: now, cal) }
        return nil
    }

    /// Sends a list and keeps its records. If there are more records than lines, the last line gives the count.
    func listAnswer(_ id: String?, title: String, records: [(RecordKind, Int64, String)], more page: String = "Today",
                    max: Int = Engine.maxListLines) -> Outgoing {
        var shown = records
        var lines: [String] = []
        if records.count > max {
            shown = Array(records.prefix(max - 1))
            lines = shown.map(\.2) + ["and \(records.count - shown.count) more"]
        } else {
            lines = shown.map(\.2)
        }
        try? store?.setLastList(shown.map { ($0.0, $0.1) })
        store?.log("list", .list, Int64(shown.count), at: clock.now)
        return .list(id, title, lines)
    }

    /// The items for "what is due": late items, then the reminders of today by time, then the to-dos that are due
    /// today and tomorrow.
    func dueItems() -> [Item] {
        guard let store else { return [] }
        let cal = clock.calendar
        let now = clock.now
        let today = Day(now, cal)
        let tomorrow = today.adding(days: 1, cal)
        let open = store.items(where: "state = 'open' AND kind != 'note'")
        var late: [Item] = [], todayReminders: [Item] = [], dueSoon: [Item] = []
        for it in open {
            if let at = it.remindAt, it.kind == .reminder {
                if at <= now && Day(at, cal) < today { late.append(it) }
                else if Day(at, cal) == today { todayReminders.append(it) }
            } else if let d = it.dueOn {
                if d < today { late.append(it) }
                else if d == today && it.kind == .reminder { todayReminders.append(it) }
                else if d == today || d == tomorrow { dueSoon.append(it) }
            }
        }
        func when(_ it: Item) -> Date { it.remindAt ?? it.dueOn?.date(cal) ?? it.createdAt }
        return late.sorted { when($0) < when($1) } + todayReminders.sorted { when($0) < when($1) }
            + dueSoon.sorted { when($0) < when($1) }
    }

    func whatIsDue(id: String) -> Outgoing {
        let items = dueItems()
        guard !items.isEmpty else { return .note(id, "Nothing is due.") }
        return listAnswer(id, title: "Due", records: items.map { (.item, $0.id, line($0)) })
    }

    /// The project for some words: the full words, or else the first word.
    func findProject(_ words: String) -> Project? {
        guard let store else { return nil }
        var w = Engine.clean(words)
        w = Engine.dropFirst(w, ["the", "my", "project"])
        if let p = store.project(named: w) { return p }
        if let first = w.split(separator: " ").first, let p = store.project(named: String(first)) { return p }
        return nil
    }

    func whatAbout(id: String, text: String) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        let words = Engine.clean(text)
        guard let p = findProject(words) else { return .note(id, "No project \(words).") }
        let open = store.items(where: "state = 'open' AND project_id = ?", [.int(p.id)])
        let dated = open.filter { $0.remindAt != nil || $0.dueOn != nil }
            .sorted { ($0.remindAt ?? $0.dueOn!.date(clock.calendar)) < ($1.remindAt ?? $1.dueOn!.date(clock.calendar)) }
        let other = open.filter { $0.remindAt == nil && $0.dueOn == nil }
        var records: [(RecordKind, Int64, String)] = (dated + other).map { (.item, $0.id, line($0)) }
        let docs = store.docs(project: p.id)
        if records.isEmpty && docs.isEmpty { return .note(id, "Project \(p.name) has no open items.") }
        // The documents line is not a record: it has no number.
        if !docs.isEmpty {
            let max = Engine.maxListLines - 1
            if records.count > max {
                let shown = Array(records.prefix(max - 1))
                try? store.setLastList(shown.map { ($0.0, $0.1) })
                let lines = shown.map(\.2) + ["and \(records.count - shown.count) more",
                                              "\(docs.count) document\(docs.count == 1 ? "" : "s")"]
                return .list(id, p.name, lines)
            }
            try? store.setLastList(records.map { ($0.0, $0.1) })
            records.append((.doc, 0, "\(docs.count) document\(docs.count == 1 ? "" : "s")"))
            return .list(id, p.name, records.map(\.2))
        }
        return listAnswer(id, title: p.name, records: records, more: p.name)
    }

    /// The words of a search: lower case, with "the" and "my" at the start removed.
    static func searchWords(_ text: String) -> [String] {
        var w = Engine.words(Engine.clean(text))
        while let f = w.first, ["the", "my", "a", "an"].contains(f) { w.removeFirst() }
        return w
    }

    func whereIs(id: String, text: String) -> Outgoing {
        guard store != nil else { return .note(id, "The PA store does not open.") }
        // A long text: the first 12 different words only. A query with 2,000 words took seconds (replay, phase 2).
        let words = Array(Fusion.unique(Engine.searchWords(String(text.prefix(Engine.maxRead)))).prefix(12))
        let shownWords = String(Engine.clean(text).prefix(80))
        guard !words.isEmpty else { return .note(id, "Nothing found for \(shownWords).") }
        let start = Date()
        let (results, byNumbers) = searchResults(words: words, query: shownWords, limit: 10)
        writeSearchPage(query: shownWords, results: results)
        sendTargets()
        log.write(clock.now, "search", ["results": String(results.count), "numbers": byNumbers ? "yes" : "no",
                                        "ms": String(Int(Date().timeIntervalSince(start) * 1000))])
        let shown = results.prefix(5)
        guard !shown.isEmpty else { return .note(id, "Nothing found for \(shownWords).") }
        return listAnswer(id, title: "Found", records: shown.map { ($0.record.0, $0.record.1, $0.line) })
    }

    static func kindLabel(_ it: Item) -> String {
        let base: String
        switch it.kind {
        case .todo: base = "to-do"
        case .reminder: base = "reminder"
        case .note: base = "note"
        }
        return it.state == .done ? base + ", done" : base
    }
}
