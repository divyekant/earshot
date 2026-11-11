import Foundation

/// The clock: alerts, the morning list, the limits and quiet time (build spec, section 10). Each rule is code with
/// fixed numbers from the settings. No model decides when to interrupt (R-PA-7).
extension Engine {
    static let ruleTime = "time"
    /// An alert whose time is more than this before the start of the PA is a missed alert.
    static let missedAfter: TimeInterval = 60

    // MARK: - Meta values

    var quietUntil: Date? {
        get { store?.meta("quiet_until").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } }
        set { try? store?.setMeta("quiet_until", newValue.map { String($0.timeIntervalSince1970) }) }
    }

    var morningShownDay: String? {
        get { store?.meta("morning_day") }
        set { try? store?.setMeta("morning_day", newValue) }
    }

    func isQuiet(_ now: Date) -> Bool { (quietUntil ?? .distantPast) > now }

    func clockTime(_ d: Date) -> ClockTime {
        let c = clock.calendar.dateComponents([.hour, .minute], from: d)
        return ClockTime(c.hour!, c.minute!)
    }

    // MARK: - Planning

    /// Plans the alert of a reminder, and marks the old alerts of the item as answered. A change by the owner
    /// (done, snooze, drop, move) is the answer to an alert.
    func planAlerts(_ it: Item, old: Item?) {
        guard let store else { return }
        let changed = old == nil || old!.remindAt != it.remindAt || old!.state != it.state || old!.kind != it.kind
        guard changed else { return }
        if old != nil {
            _ = try? store.db.run("UPDATE alert SET state = 'answered' WHERE item_id = ? AND state IN ('planned', 'shown', 'repeated', 'held', 'moved_to_list')",
                                  [.int(it.id)])
            if old!.state == .open && it.state != .open { store.log("alert-answer", .item, it.id, at: clock.now) }
        }
        if it.state == .open, it.kind == .reminder, let at = it.remindAt {
            _ = try? store.insertAlert(PlannedAlert(itemID: it.id, rule: Engine.ruleTime, fireAt: at))
        }
    }

    // MARK: - The tick

    /// The next time that the clock must check. The program sets one timer for it, and checks at least each 60 s.
    public func nextCheck() -> Date? {
        guard let store else { return nil }
        let now = clock.now
        var times: [Date] = []
        if let a = store.alerts(where: "state = 'planned'").first { times.append(a.fireAt) }
        let repeatAfter = TimeInterval(settings.repeatAfterMinutes * 60)
        if let a = store.alerts(where: "state IN ('shown', 'repeated') AND shown_at IS NOT NULL", order: "shown_at").first,
           let s = a.shownAt { times.append(s.addingTimeInterval(repeatAfter)) }
        if let q = quietUntil, q > now { times.append(q) }
        times.append(nextMorning(now))
        if pagesDirty, let w = pagesWrittenAt { times.append(w.addingTimeInterval(1)) }
        return times.min()
    }

    func morningTime(on day: Day) -> Date {
        let m = settings.morningTime
        return day.date(clock.calendar, hour: m.hour, minute: m.minute)
    }

    func nextMorning(_ now: Date) -> Date {
        let today = Day(now, clock.calendar)
        if morningShownDay != today.description { return morningTime(on: today) }
        return morningTime(on: today.adding(days: 1, clock.calendar))
    }

    /// Checks all the rules. The program calls it at the timer, at a wake from sleep, at a change of the clock,
    /// and each 60 s.
    public func tick() {
        guard store != nil else { return }
        reloadSettingsIfChanged()
        care()
        let now = clock.now
        if let q = quietUntil, q <= now {
            quietUntil = nil
            releaseHeld(title: "While quiet")
        }
        fireAlerts(now)
        repeatAlerts(now)
        morningList(now)
        clockTicked()
        checkFilesIfDue()
        // The pages show "today" and "late": write them again when the day changes.
        if store?.meta("pages_day") != Day(now, clock.calendar).description {
            try? store?.setMeta("pages_day", Day(now, clock.calendar).description)
            markPagesDirty()
        }
        flushPages()
    }

    /// Other packages act at each tick (the copy in Reminders, the pages).
    func clockTicked() {
        // A safety net for the copy in Reminders: read the list each 5 minutes, also if EventKit reported nothing.
        if mirrorOn, (lastPull.map { clock.now.timeIntervalSince($0) >= 300 } ?? true) {
            lastPull = clock.now
            pull()
        }
    }

    /// One time each day: the daily copy, and the delete of records that were dropped 30 days ago.
    func care() {
        guard let store else { return }
        let today = Day(clock.now, clock.calendar)
        guard store.meta("care_day") != today.description else { return }
        try? store.backup(folder: backupsFolder, day: today, keep: 7)
        try? store.purgeDropped(before: clock.now.addingTimeInterval(-30 * 86400))
        try? store.setMeta("care_day", today.description)
        log.write(clock.now, "care")
    }

    /// The alert line of an item.
    func alertText(_ it: Item) -> String { "Reminder · " + (it.title.isEmpty ? it.said : it.title) }

    func alertsShownInLastHour(_ now: Date) -> Int {
        let since = now.addingTimeInterval(-3600).timeIntervalSince1970
        let rows = (try? store?.db.query("SELECT COUNT(*) FROM event WHERE type IN ('alert-shown', 'alert-repeat') AND at >= ?", [.real(since)])) ?? []
        return Int(rows.first?.first?.int ?? 0)
    }

    /// True if the copy in Apple Reminders gives the alert of this item, so that earshot does not alert again.
    func remindersGiveAlert(_ it: Item) -> Bool {
        guard settings.reminders.copy, settings.reminders.alertBy == "reminders", let reminders, reminders.access == .allowed,
              let store else { return false }
        return store.mirrors().contains { $0.itemID == it.id }
    }

    func fireAlerts(_ now: Date) {
        guard let store else { return }
        for var a in store.alerts(where: "state = 'planned' AND fire_at <= ?", [.real(now.timeIntervalSince1970)]) {
            guard let iid = a.itemID, let it = store.item(iid), it.state == .open else {
                a.state = .answered; try? store.updateAlert(a); continue
            }
            let mode = settings.rules(project: projectName(it.projectID)).time
            if mode == .off { a.state = .answered; try? store.updateAlert(a); continue }
            if mode == .list { a.state = .movedToList; try? store.updateAlert(a); continue }
            if remindersGiveAlert(it) {
                // The Reminders app alerts. The PA records the alert, so that "done" with no words works.
                a.state = .shown; a.shownAt = now; try? store.updateAlert(a)
                a.state = .repeated; try? store.updateAlert(a)
                store.log("alert-by-reminders", .item, iid, at: now)
                continue
            }
            if isQuiet(now) { a.state = .held; try? store.updateAlert(a); continue }
            // Quiet hours: wait for the morning list. A clock time that the owner said in these hours still alerts.
            let saidInQuietHours = it.hasClock && settings.quietHours.contains(clockTime(it.remindAt ?? a.fireAt))
            if settings.quietHours.contains(clockTime(now)) && !saidInQuietHours {
                a.state = .movedToList; try? store.updateAlert(a)
                store.log("alert-to-list", .item, iid, at: now)
                continue
            }
            if alertsShownInLastHour(now) >= settings.maxAlertsPerHour {
                a.state = .movedToList; try? store.updateAlert(a)
                store.log("alert-to-list", .item, iid, at: now)
                continue
            }
            output.send(.alert(alertText(it)))
            a.state = .shown; a.shownAt = now; try? store.updateAlert(a)
            store.log("alert-shown", .item, iid, at: now)
            log.write(now, "alert", ["item": String(iid)])
        }
    }

    /// A reminder with no answer in 10 minutes shows one more time. After that, it goes to the morning list.
    func repeatAlerts(_ now: Date) {
        guard let store else { return }
        let limit = now.addingTimeInterval(-TimeInterval(settings.repeatAfterMinutes * 60)).timeIntervalSince1970
        for var a in store.alerts(where: "state IN ('shown', 'repeated') AND shown_at <= ?", [.real(limit)]) {
            guard let iid = a.itemID, let it = store.item(iid), it.state == .open else {
                a.state = .answered; try? store.updateAlert(a); continue
            }
            if a.state == .repeated {
                a.state = .movedToList; try? store.updateAlert(a)
                store.log("alert-no-answer", .item, iid, at: now)
                continue
            }
            if isQuiet(now) || alertsShownInLastHour(now) >= settings.maxAlertsPerHour {
                a.state = .movedToList; try? store.updateAlert(a)
                store.log("alert-no-answer", .item, iid, at: now)
                continue
            }
            output.send(.alert(alertText(it)))
            a.state = .repeated; a.shownAt = now; try? store.updateAlert(a)
            store.log("alert-repeat", .item, iid, at: now)
            log.write(now, "alert-repeat", ["item": String(iid)])
        }
    }

    /// At a start: the reminders that were missed while the PA did not run, as one list "Missed".
    func missedList(at start: Date) {
        guard let store else { return }
        let before = start.addingTimeInterval(-Engine.missedAfter).timeIntervalSince1970
        var records: [(RecordKind, Int64, String)] = []
        for var a in store.alerts(where: "state = 'planned' AND fire_at < ?", [.real(before)]) {
            a.state = .movedToList
            try? store.updateAlert(a)
            guard let iid = a.itemID, let it = store.item(iid), it.state == .open else { continue }
            records.append((.item, iid, line(it)))
            store.log("alert-missed", .item, iid, at: start)
        }
        guard !records.isEmpty else { return }
        output.send(listAnswer(nil, title: "Missed", records: records))
    }

    /// The alerts that "quiet" held, as one list.
    func releaseHeld(title: String) {
        guard let store else { return }
        var records: [(RecordKind, Int64, String)] = []
        for var a in store.alerts(where: "state = 'held'") {
            a.state = .movedToList
            try? store.updateAlert(a)
            if let iid = a.itemID, let it = store.item(iid), it.state == .open { records.append((.item, iid, line(it))) }
        }
        guard !records.isEmpty else { return }
        output.send(listAnswer(nil, title: title, records: records))
    }

    // MARK: - The morning list

    /// The items of the morning list: the reminders of today, the to-dos that are due, the quiet items.
    func morningItems(_ now: Date) -> [Item] {
        guard let store else { return [] }
        let cal = clock.calendar
        let today = Day(now, cal)
        let tomorrow = today.adding(days: 1, cal)
        let open = store.items(where: "state = 'open' AND kind != 'note'")
        func rules(_ it: Item) -> RuleModes { settings.rules(project: projectName(it.projectID)) }
        var reminders: [Item] = [], due: [Item] = [], quiet: [Item] = []
        for it in open {
            if it.kind == .reminder {
                if let at = it.remindAt, Day(at, cal) <= today, rules(it).time != .off { reminders.append(it); continue }
                if it.remindAt == nil, let d = it.dueOn, d <= today, rules(it).time != .off { reminders.append(it); continue }
            } else if let d = it.dueOn, d <= tomorrow, rules(it).due != .off {
                due.append(it); continue
            }
            if rules(it).silence != .off {
                let words = Engine.words(it.said)
                let waiting = words.starts(with: ["waiting", "for"])
                let days = TimeInterval((waiting ? settings.waitingDays : settings.silenceDays) * 86400)
                if (it.kind == .todo || waiting) && now.timeIntervalSince(it.updatedAt) >= days { quiet.append(it) }
            }
        }
        func when(_ it: Item) -> Date { it.remindAt ?? it.dueOn?.date(cal) ?? it.createdAt }
        return reminders.sorted { when($0) < when($1) } + due.sorted { when($0) < when($1) } + quiet.sorted { $0.updatedAt < $1.updatedAt }
    }

    /// One time each day at the morning time. If the PA did not run at that time, at the first check after it.
    func morningList(_ now: Date) {
        let today = Day(now, clock.calendar)
        guard morningShownDay != today.description, now >= morningTime(on: today), !isQuiet(now) else { return }
        morningShownDay = today.description
        let items = morningItems(now)
        store?.log("morning", .list, Int64(items.count), at: now)
        guard !items.isEmpty else { return }
        output.send(listAnswer(nil, title: "Today", records: items.map { (.item, $0.id, line($0)) }, max: 7))
    }

    // MARK: - Quiet

    func quiet(id: String, text: String) -> Outgoing {
        let t = Engine.clean(text)
        let now = clock.now
        let lower = t.lowercased()
        if ["off", "stop", "end", "over"].contains(lower) {
            quietUntil = nil
            store?.log("quiet-off", nil, nil, at: now)
            releaseHeld(title: "While quiet")
            return .note(id, "Quiet is off.")
        }
        var until: Date?
        if t.isEmpty {
            until = now.addingTimeInterval(3600)
        } else {
            var words = t
            if lower.hasPrefix("for ") { words = "in " + t.dropFirst(4) }
            if lower.hasPrefix("till ") || lower.hasPrefix("until ") {
                words = String(t.drop(while: { $0 != " " })).trimmingCharacters(in: .whitespaces)
                if Int(words.split(separator: " ").first ?? "") != nil && !words.contains(":") { words = "at " + words }
            }
            let r = TimeReader(calendar: clock.calendar, settings: settings).read(words, now: now)
            if r.kind != .none, r.rest.isEmpty {
                until = r.at ?? r.day.map { morningTime(on: $0) }
            }
        }
        guard let until, until > now else { return .note(id, "No time. Quiet did not change.") }
        quietUntil = until
        store?.log("quiet", nil, nil, at: now)
        return .note(id, "Quiet · until " + TimeText.moment(until, now: now, clock.calendar, locale: clock.locale)
                     .replacingOccurrences(of: "today ", with: ""))
    }
}
