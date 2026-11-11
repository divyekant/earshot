import Foundation

public enum ItemKind: String, Sendable, CaseIterable {
    case todo, reminder, note
}

public enum ItemState: String, Sendable {
    case open, done, dropped
}

/// One to-do, reminder or note.
public struct Item: Equatable, Sendable {
    public var id: Int64 = 0
    public var kind: ItemKind
    /// The full words after the lead, as the owner said them.
    public var said: String
    /// The words with the time words and the project cut. The PA shows this.
    public var title: String
    public var state: ItemState = .open
    /// The time of the reminder. For a to-do with a clock time, the due time.
    public var remindAt: Date?
    /// The due day, or the day of a reminder with no clock time.
    public var dueOn: Day?
    /// True if the owner said a clock time.
    public var hasClock = false
    public var projectID: Int64?
    public var docID: Int64?
    /// The bundle id of the front app at the capture.
    public var contextApp: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var doneAt: Date?
    public var droppedAt: Date?

    public init(kind: ItemKind, said: String, title: String, createdAt: Date) {
        self.kind = kind; self.said = said; self.title = title
        self.createdAt = createdAt; self.updatedAt = createdAt
    }
}

public struct Project: Equatable, Sendable {
    public var id: Int64 = 0
    public var name: String
    public var slug: String
    public var state: String = "open"
    public var createdAt: Date
    public var aliases: [String] = []

    public init(name: String, slug: String, createdAt: Date) {
        self.name = name; self.slug = slug; self.createdAt = createdAt
    }
}

/// A reference to a document or a web page. The PA keeps the address and the title, not the document.
public struct Doc: Equatable, Sendable {
    public var id: Int64 = 0
    public var address: String?
    public var title: String
    public var app: String?
    public var projectID: Int64?
    public var createdAt: Date
    public var droppedAt: Date?

    public init(address: String?, title: String, app: String?, projectID: Int64?, createdAt: Date) {
        self.address = address; self.title = title; self.app = app; self.projectID = projectID; self.createdAt = createdAt
    }
}

public enum AlertState: String, Sendable {
    case planned, shown, repeated, answered
    case movedToList = "moved_to_list"
    /// Held by "quiet". The PA shows it in one list after the quiet time.
    case held
}

/// One planned alert. `itemID` is nil for the morning list.
public struct PlannedAlert: Equatable, Sendable {
    public var id: Int64 = 0
    public var itemID: Int64?
    public var rule: String
    public var fireAt: Date
    public var state: AlertState = .planned
    public var shownAt: Date?

    public init(itemID: Int64?, rule: String, fireAt: Date) {
        self.itemID = itemID; self.rule = rule; self.fireAt = fireAt
    }
}

/// The kind of record in a list, the search index, the event table and the mirror.
public enum RecordKind: String, Sendable {
    case item, project, doc, alert, list, settings, mirror, store
}

/// One pair of the copy in Apple Reminders.
public struct MirrorRow: Equatable, Sendable {
    public var itemID: Int64
    public var reminderID: String
    public var syncedPrint: String
    public var syncedAt: Date

    public init(itemID: Int64, reminderID: String, syncedPrint: String, syncedAt: Date) {
        self.itemID = itemID; self.reminderID = reminderID; self.syncedPrint = syncedPrint; self.syncedAt = syncedAt
    }
}
