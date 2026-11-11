import Foundation

/// The two-way copy of open to-dos and reminders in one Apple Reminders list (build spec 11.3). The PA store stays
/// the source. Reminders is a copy, for the view and for the iPhone. macOS does the iCloud sync (R-PA-2).
extension Engine {
    static let deniedNote = "The PA has no access to Reminders. The copy is off."

    var mirrorOn: Bool { settings.reminders.copy && reminders?.access == .allowed }

    var listIDKey: String { "reminders_list_id" }

    /// The record of an item in Reminders: the title, the time, the project. Not the said text, not notes.
    func reminderRecord(_ it: Item, id: String?) -> ReminderRecord {
        let cal = clock.calendar
        var r = ReminderRecord(id: id, title: it.title.isEmpty ? it.said : it.title)
        if let at = it.remindAt {
            r.dueDay = Day(at, cal)
            if it.hasClock { r.dueClock = clockTime(at) }
            if it.kind == .reminder && settings.reminders.alertBy == "reminders" { r.alarm = at }
        } else if let d = it.dueOn {
            r.dueDay = d
        }
        if let p = projectName(it.projectID) { r.notes = "Project: \(p)" }
        r.completed = it.state == .done
        return r
    }

    /// The print of a reminder: the title, the time and the state. A change of the print is a change to copy.
    static func print(_ r: ReminderRecord) -> String {
        [r.title, r.dueDay?.description ?? "-", r.dueClock?.description ?? "-", r.completed ? "done" : "open"].joined(separator: "|")
    }

    func listID() -> String? {
        guard let reminders, let store else { return nil }
        do {
            let id = try reminders.ensureList(named: settings.reminders.list, knownID: store.meta(listIDKey))
            if store.meta(listIDKey) != id { try? store.setMeta(listIDKey, id) }
            return id
        } catch {
            log.write(clock.now, "mirror-list-failed")
            return nil
        }
    }

    /// At hello: ask for access if needed, then copy all.
    func startMirror() {
        guard settings.reminders.copy, let reminders else { return }
        switch reminders.access {
        case .allowed:
            syncAll()
        case .notAsked:
            reminders.requestAccess { [weak self] result in
                self?.runLater(0) {
                    guard let self else { return }
                    self.log.write(self.clock.now, "reminders-access", ["result": "\(result)".replacingOccurrences(of: " ", with: "_")])
                    if result == .allowed { self.syncAll() } else { self.announceDenied() }
                }
            }
        case .denied, .failed:
            announceDenied()
        }
        reminders.onChange = { [weak self] in
            // EventKit reports a change: wait 2 s, then read the list.
            self?.runLater(2) { self?.pull() }
        }
    }

    func announceDenied() {
        guard store?.meta("reminders_denied_note") == nil else { return }
        try? store?.setMeta("reminders_denied_note", "1")
        output.send(.note(nil, Engine.deniedNote))
    }

    /// Copies each open to-do and reminder that has no copy, then reads the list.
    func syncAll() {
        guard mirrorOn, let store else { return }
        try? store.setMeta("reminders_denied_note", nil)
        let rows = Set(store.mirrors().map(\.itemID))
        for it in store.items(where: "state = 'open' AND kind != 'note'") where !rows.contains(it.id) { push(it) }
        pull()
    }

    /// PA to Reminders, for one changed item.
    func push(_ it: Item) {
        guard mirrorOn, let store, let reminders, it.kind != .note else { return }
        guard let list = listID() else { return }
        let row = store.mirrors().first { $0.itemID == it.id }
        do {
            if it.state == .dropped {
                if let row {
                    try reminders.remove(id: row.reminderID)
                    try store.removeMirror(itemID: it.id)
                    store.log("sync-push", .item, it.id, at: clock.now)
                }
                return
            }
            if row == nil && it.state != .open { return }
            let rec = reminderRecord(it, id: row?.reminderID)
            let p = Engine.print(rec)
            if let row, row.syncedPrint == p { return }
            let rid = try reminders.save(rec, list: list)
            try store.setMirror(MirrorRow(itemID: it.id, reminderID: rid, syncedPrint: p, syncedAt: clock.now))
            store.log("sync-push", .item, it.id, at: clock.now)
        } catch {
            log.write(clock.now, "sync-push-failed", ["item": String(it.id)])
        }
    }

    /// Reminders to PA: ticks, changes, deletes, and new reminders from the iPhone.
    func pull() {
        guard mirrorOn, let store, let reminders, let list = listID() else { return }
        let found: [ReminderRecord]
        do { found = try reminders.reminders(list: list) } catch {
            log.write(clock.now, "sync-pull-failed")
            return
        }
        let now = clock.now
        let rows = store.mirrors()
        var byReminder: [String: MirrorRow] = [:]
        for r in rows { byReminder[r.reminderID] = r }
        var seen = Set<String>()
        for r in found {
            guard let rid = r.id else { continue }
            seen.insert(rid)
            let p = Engine.print(r)
            if let row = byReminder[rid] {
                guard var it = store.item(row.itemID), it.state != .dropped else {
                    try? reminders.remove(id: rid)
                    try? store.removeMirror(itemID: row.itemID)
                    continue
                }
                if p == row.syncedPrint { continue }
                let itemPrint = Engine.print(reminderRecord(it, id: rid))
                let itemChangedToo = itemPrint != row.syncedPrint
                if itemChangedToo, (r.modifiedAt ?? .distantPast) < it.updatedAt {
                    // Both changed: the newer change wins. Here the PA item is newer.
                    store.log("sync-conflict", .item, it.id, at: now)
                    push(it)
                    continue
                }
                if itemChangedToo { store.log("sync-conflict", .item, it.id, at: now) }
                let old = it
                apply(r, to: &it)
                it.updatedAt = now
                do {
                    try store.update(it, event: "sync-pull", at: now)
                    try store.setMirror(MirrorRow(itemID: it.id, reminderID: rid, syncedPrint: p, syncedAt: now))
                } catch { continue }
                planAlerts(it, old: old)
                markPagesDirty()
            } else if !r.completed {
                // A reminder that the owner added in the "earshot" list, for example on the iPhone: a new item.
                var it = Item(kind: r.dueClock != nil ? .reminder : .todo, said: r.title, title: r.title, createdAt: now)
                apply(r, to: &it)
                do {
                    it.id = try store.insert(it, event: "capture-reminders")
                    try store.setMirror(MirrorRow(itemID: it.id, reminderID: rid, syncedPrint: p, syncedAt: now))
                } catch { continue }
                planAlerts(it, old: nil)
                markPagesDirty()
            }
        }
        // A reminder that is gone: drop the item.
        for row in rows where !seen.contains(row.reminderID) {
            try? store.removeMirror(itemID: row.itemID)
            guard var it = store.item(row.itemID), it.state == .open else { continue }
            let old = it
            it.state = .dropped
            it.droppedAt = now
            it.updatedAt = now
            try? store.update(it, event: "drop-reminders", at: now)
            planAlerts(it, old: old)
            markPagesDirty()
        }
        flushPages()
    }

    /// Takes the title, the time and the state of a reminder into an item.
    func apply(_ r: ReminderRecord, to it: inout Item) {
        let title = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != it.title { it.title = title }
        if let d = r.dueDay {
            if let c = r.dueClock {
                it.remindAt = d.date(clock.calendar, hour: c.hour, minute: c.minute)
                it.hasClock = true
                if it.kind == .todo { it.dueOn = d } else { it.dueOn = nil }
            } else {
                if it.kind == .reminder {
                    let m = settings.dayParts.morning
                    let at = d.date(clock.calendar, hour: m.hour, minute: m.minute)
                    it.remindAt = at > clock.now ? at : nil
                    it.dueOn = at > clock.now ? nil : d
                } else {
                    it.remindAt = nil
                    it.dueOn = d
                }
                it.hasClock = false
            }
        } else {
            it.remindAt = nil
            it.dueOn = nil
            it.hasClock = false
        }
        if r.completed && it.state == .open {
            it.state = .done
            it.doneAt = clock.now
        } else if !r.completed && it.state == .done {
            it.state = .open
            it.doneAt = nil
        }
    }

    /// The copy changed from on to off: read one last time, then remove the list.
    func stopMirror() {
        guard let store, let reminders, reminders.access == .allowed else { return }
        var s = settings
        s.reminders.copy = true
        let real = settings
        settings = s
        pull()
        settings = real
        if let id = store.meta(listIDKey) { try? reminders.removeList(id: id) }
        _ = try? store.db.run("DELETE FROM mirror")
        try? store.setMeta(listIDKey, nil)
        store.log("sync-off", nil, nil, at: clock.now)
    }
}
