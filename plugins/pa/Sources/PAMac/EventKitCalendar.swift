#if os(macOS)
import EventKit
import Foundation
import PACore

/// The calendar source of the PA (phase 3, 9.1): EventKit, full access, read only. It never saves or removes an
/// event (rule 1, `ReadOnlyTests`). The Calendar app does not have to run.
public final class EventKitCalendar: CalendarSource {
    let store = EKEventStore()
    var observer: NSObjectProtocol?

    /// `onChange` runs after the access question and at each change of the calendar store.
    public init(ask: Bool, onChange: @escaping () -> Void) {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
            onChange()
        }
        if ask, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            store.requestFullAccessToEvents { _, _ in onChange() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    public var access: SourceAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    public func events(from: Date, to: Date) throws -> [CalEvent] {
        guard access == .allowed else { return [] }
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: pred).compactMap { e -> CalEvent? in
            if e.isAllDay || e.status == .canceled { return nil }
            // An event that the owner declined.
            if let me = e.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { return nil }
            let people = (e.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(\.name)
            let id = (e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString)
                + "@" + String(Int(e.startDate.timeIntervalSince1970))
            return CalEvent(sourceID: id, title: e.title ?? "", startsAt: e.startDate, endsAt: e.endDate,
                            allDay: e.isAllDay, people: people, place: e.location)
        }
    }
}
#endif
