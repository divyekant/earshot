#if canImport(EventKit)
import EventKit
import Foundation
import PACore

/// Apple Reminders through EventKit. The PA reads and changes only its own list. macOS does the iCloud sync, so the
/// PA has no network code (R-PA-2).
public final class EventKitStore: ReminderStore {
    let store = EKEventStore()
    public var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    public init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { [weak self] _ in
            self?.onChange?()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    public var access: ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .allowed
        case .notDetermined: return .notAsked
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    public func requestAccess(_ done: @escaping (ReminderAccess) -> Void) {
        store.requestFullAccessToReminders { granted, error in
            if let error { done(.failed(String(describing: error))); return }
            done(granted ? .allowed : .denied)
        }
    }

    public func ensureList(named: String, knownID: String?) throws -> String {
        if let knownID, let cal = store.calendar(withIdentifier: knownID), cal.allowedEntityTypes.contains(.reminder) {
            return cal.calendarIdentifier
        }
        if let cal = store.calendars(for: .reminder).first(where: { $0.title == named }) {
            return cal.calendarIdentifier
        }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = named
        // The source of the default list: iCloud if the owner uses it, so the list shows on the iPhone.
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV })
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw NSError(domain: "PA", code: 1, userInfo: [NSLocalizedDescriptionKey: "no source for a new list"])
        }
        cal.source = source
        try store.saveCalendar(cal, commit: true)
        return cal.calendarIdentifier
    }

    public func reminders(list: String) throws -> [ReminderRecord] {
        guard let cal = store.calendar(withIdentifier: list) else {
            throw NSError(domain: "PA", code: 2, userInfo: [NSLocalizedDescriptionKey: "the list is gone"])
        }
        let predicate = store.predicateForReminders(in: [cal])
        let sem = DispatchSemaphore(value: 0)
        var found: [EKReminder] = []
        store.fetchReminders(matching: predicate) { rs in
            found = rs ?? []
            sem.signal()
        }
        if sem.wait(timeout: .now() + 10) == .timedOut {
            throw NSError(domain: "PA", code: 3, userInfo: [NSLocalizedDescriptionKey: "Reminders did not answer"])
        }
        return found.map(Self.record)
    }

    static func record(_ r: EKReminder) -> ReminderRecord {
        var day: Day?
        var clock: ClockTime?
        if let c = r.dueDateComponents, let y = c.year, let m = c.month, let d = c.day {
            day = Day(y, m, d)
            if let h = c.hour, h != NSDateComponentUndefined { clock = ClockTime(h, (c.minute == NSDateComponentUndefined ? 0 : c.minute) ?? 0) }
        }
        let alarm = r.alarms?.compactMap(\.absoluteDate).min()
        return ReminderRecord(id: r.calendarItemIdentifier, title: r.title ?? "", dueDay: day, dueClock: clock, alarm: alarm,
                              notes: r.notes, completed: r.isCompleted, modifiedAt: r.lastModifiedDate)
    }

    public func save(_ rec: ReminderRecord, list: String) throws -> String {
        let r: EKReminder
        if let id = rec.id, let old = store.calendarItem(withIdentifier: id) as? EKReminder {
            r = old
        } else {
            guard let cal = store.calendar(withIdentifier: list) else {
                throw NSError(domain: "PA", code: 2, userInfo: [NSLocalizedDescriptionKey: "the list is gone"])
            }
            r = EKReminder(eventStore: store)
            r.calendar = cal
        }
        r.title = rec.title
        r.notes = rec.notes
        if let d = rec.dueDay {
            var c = DateComponents(year: d.year, month: d.month, day: d.day)
            if let t = rec.dueClock { c.hour = t.hour; c.minute = t.minute }
            r.dueDateComponents = c
        } else {
            r.dueDateComponents = nil
        }
        for a in r.alarms ?? [] { r.removeAlarm(a) }
        if let alarm = rec.alarm { r.addAlarm(EKAlarm(absoluteDate: alarm)) }
        r.isCompleted = rec.completed
        try store.save(r, commit: true)
        return r.calendarItemIdentifier
    }

    public func remove(id: String) throws {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(r, commit: true)
    }

    public func removeList(id: String) throws {
        guard let cal = store.calendar(withIdentifier: id) else { return }
        try store.removeCalendar(cal, commit: true)
    }
}
#endif
