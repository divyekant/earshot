import Foundation

/// The state of the access to Apple Reminders.
public enum ReminderAccess: Equatable, Sendable {
    case allowed
    case denied
    /// macOS did not ask yet.
    case notAsked
    /// macOS gave an error, or showed no question.
    case failed(String)
}

/// One reminder in the list of the PA in Apple Reminders.
public struct ReminderRecord: Equatable, Sendable {
    /// The identifier of EventKit. Nil for a new reminder.
    public var id: String?
    public var title: String
    /// The due day. With `dueClock`, also a time.
    public var dueDay: Day?
    /// The clock time of the due date, in minutes after midnight. Nil for a day with no time.
    public var dueClock: ClockTime?
    /// The time of the alarm. Nil for no alarm.
    public var alarm: Date?
    public var notes: String?
    public var completed: Bool
    public var modifiedAt: Date?

    public init(id: String? = nil, title: String, dueDay: Day? = nil, dueClock: ClockTime? = nil, alarm: Date? = nil,
                notes: String? = nil, completed: Bool = false, modifiedAt: Date? = nil) {
        self.id = id; self.title = title; self.dueDay = dueDay; self.dueClock = dueClock; self.alarm = alarm
        self.notes = notes; self.completed = completed; self.modifiedAt = modifiedAt
    }
}

/// Apple Reminders, behind a protocol. The program uses EventKit (PAMac). Tests use a fake.
/// The PA reads and changes only its own list.
public protocol ReminderStore: AnyObject {
    var access: ReminderAccess { get }
    /// Asks macOS for full access to reminders. macOS shows its question one time.
    func requestAccess(_ done: @escaping (ReminderAccess) -> Void)
    /// The identifier of the list with this name. Makes the list if it is not there.
    func ensureList(named: String, knownID: String?) throws -> String
    func reminders(list: String) throws -> [ReminderRecord]
    /// Saves a new or changed reminder. Gives its identifier.
    func save(_ r: ReminderRecord, list: String) throws -> String
    func remove(id: String) throws
    func removeList(id: String) throws
    /// Called when Reminders reports a change. The PA sets it.
    var onChange: (() -> Void)? { get set }
}
