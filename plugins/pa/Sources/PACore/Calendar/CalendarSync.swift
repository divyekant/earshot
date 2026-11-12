import Foundation

/// Phase 3, package S3: the calendar read (9.1) and the near-event alert (9.3).
extension Engine {
    /// The PA reads the next 14 days.
    static let calendarDays: TimeInterval = 14 * 86400
    /// The PA reads again each 15 minutes, also if EventKit reported no change.
    static let calendarEvery: TimeInterval = 15 * 60

    /// Reads the events of the next 14 days into the store, and deletes the old ones. The source skips declined,
    /// cancelled and all-day events. Call it at the start, at a change of the EventKit store, and each 15 minutes.
    public func readCalendar() {
        lastCalendarRead = clock.now
        guard settings.sources.calendar, let store, let source = calendarSource, source.access == .allowed else { return }
        let now = clock.now
        // From now minus 1 day, so that an event that runs now stays.
        let from = now.addingTimeInterval(-86400)
        do {
            let events = try source.events(from: from, to: now.addingTimeInterval(Engine.calendarDays))
            for e in events where !e.allDay { try store.upsertEvent(e) }
            try store.pruneEvents(now: now, keep: Set(events.map(\.sourceID)), readFrom: from)
            log.write(now, "calendar-read", ["events": String(events.count)])
            linkEventsByRule()
        } catch {
            log.write(now, "calendar-error")
        }
        markPagesDirty()
    }

    func readCalendarIfDue() {
        guard calendarSource != nil else { return }
        if let last = lastCalendarRead, clock.now.timeIntervalSince(last) < Engine.calendarEvery { return }
        readCalendar()
    }

    /// The records of an event for the alert: the open to-dos and notes (reminders have their own alert), then the
    /// documents. Each line is a title.
    func eventRecords(_ e: CalEvent) -> (items: [Item], docs: [Doc]) {
        guard let store else { return ([], []) }
        var items: [Item] = [], docs: [Doc] = []
        for l in store.eventLinks(e.id) {
            if let iid = l.itemID, let it = store.item(iid), it.state == .open, it.kind != .reminder,
               !items.contains(where: { $0.id == iid }) { items.append(it) }
            if let did = l.docID, let d = store.doc(did), d.droppedAt == nil, !docs.contains(where: { $0.id == did }) { docs.append(d) }
        }
        return (Array(items.prefix(EventLinker.maxItems)), Array(docs.prefix(EventLinker.maxDocs)))
    }

    func eventAlertTime(_ e: CalEvent) -> Date {
        e.startsAt.addingTimeInterval(-TimeInterval(settings.nearEventMinutes * 60))
    }

    func eventAlertDone(_ e: CalEvent) -> Bool {
        guard let store else { return true }
        let n = (try? store.db.query("SELECT COUNT(*) FROM event WHERE type = 'event-alert' AND record_kind = 'cal_event' AND record_id = ?",
                                     [.int(e.id)]))?.first?.first?.int ?? 0
        return n > 0
    }

    /// The next time of a near-event alert, for the timer.
    func nextEventAlert(_ now: Date) -> Date? {
        guard let store, calendarSource != nil else { return nil }
        return store.events(from: now, to: now.addingTimeInterval(Engine.calendarDays))
            .filter { !eventAlertDone($0) && !(eventRecords($0).items.isEmpty && eventRecords($0).docs.isEmpty) }
            .map(eventAlertTime).filter { $0 > now }.min()
    }

    /// Rule 2 (9.3): `nearEventMinutes` before the start of an event with links, an alert with a list. Line 1 is the
    /// event with its time, then the linked items and documents. If the Mac was asleep at the alert time and the event
    /// did not end yet, the alert shows at the wake. After the end, it shows nothing.
    func nearEventAlerts(_ now: Date) {
        guard let store, settings.sources.calendar else { return }
        for e in store.events(from: now.addingTimeInterval(-Engine.calendarDays), to: now.addingTimeInterval(Engine.calendarDays))
        where eventAlertTime(e) <= now && e.endsAt > now && !eventAlertDone(e) {
            let (items, docs) = eventRecords(e)
            guard !items.isEmpty || !docs.isEmpty else { continue }
            // The mode of the event: the project of the first linked item, or the general value.
            let mode = settings.rules(project: projectName(items.first?.projectID ?? docs.first?.projectID)).nearEvent
            store.log("event-alert", .calEvent, e.id, at: now)
            guard mode == .alert else { continue }
            if isQuiet(now) || settings.quietHours.contains(clockTime(now)) || alertsShownInLastHour(now) >= settings.maxAlertsPerHour {
                store.log("event-alert-to-list", .calEvent, e.id, at: now)
                continue
            }
            let head = e.title + " · " + TimeText.clock(e.startsAt, clock.calendar, locale: clock.locale)
            let owned = store.eventLinks(e.id).filter { $0.by == "owner" }
            let lines = items.map { it in linkedLine(it.title.isEmpty ? it.said : it.title, byOwner: owned.contains { $0.itemID == it.id }) }
                + docs.map { d in linkedLine(d.title, byOwner: owned.contains { $0.docID == d.id }) }
            output.send(.answer(re: nil, kind: .alert, text: head, items: lines))
            store.log("alert-shown", .calEvent, e.id, at: now)
            log.write(now, "event-alert", ["items": String(items.count), "docs": String(docs.count)])
        }
    }

    /// Rule 2 with the mode "list": the linked events of today in the morning list, 2 lines or fewer.
    func eventsForMorning(_ now: Date) -> [(Int64, String)] {
        guard let store, settings.sources.calendar else { return [] }
        let cal = clock.calendar
        let start = cal.startOfDay(for: now)
        return store.events(from: start, to: start.addingTimeInterval(86400)).compactMap { e -> (Int64, String)? in
            let (items, docs) = eventRecords(e)
            guard !items.isEmpty || !docs.isEmpty else { return nil }
            let mode = settings.rules(project: projectName(items.first?.projectID ?? docs.first?.projectID)).nearEvent
            guard mode == .list else { return nil }
            return (e.id, "\(TimeText.clock(e.startsAt, cal, locale: clock.locale)) · \(e.title) · \(items.count + docs.count) linked")
        }.prefix(2).map { $0 }
    }
}
