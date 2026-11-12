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
    /// Who set the project: "owner" (the words or a move) or "search" (a proposal, phase 2 build spec 8.1).
    public var projectBy: String?
    /// The score of a proposal of the search.
    public var projectScore: Double?

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
    /// The time of "finish project". A closed project is not a target and gets no proposals.
    public var closedAt: Date?

    public init(name: String, slug: String, createdAt: Date) {
        self.name = name; self.slug = slug; self.createdAt = createdAt
    }
}

/// The kind of a kept reference.
public enum DocKind: String, Sendable {
    case file, page, folder
    /// A note of the Notes app (phase 3, S6). It has no address that the PA can open.
    case note
}

/// The state of the text of a kept file (phase 2 build spec, 7.3).
public enum TextState: String, Sendable {
    /// No text to read: a web page, a reference, or a file type that the PA does not read.
    case none
    case queued
    case read
    /// A PDF with no text, for example a scan.
    case noText = "no_text"
    case tooLarge = "too_large"
    case noAccess = "no_access"
    case gone
}

/// A reference to a document or a web page. For a page, the PA keeps the address and the title. For a kept file,
/// the PA also reads the text into index.sqlite. It never changes, moves or deletes the file (R-PA-3).
public struct Doc: Equatable, Sendable {
    public var id: Int64 = 0
    public var address: String?
    public var title: String
    public var app: String?
    public var projectID: Int64?
    public var createdAt: Date
    public var droppedAt: Date?
    /// The file path of a kept file or folder.
    public var path: String?
    public var kind: DocKind = .page
    public var size: Int64?
    public var modifiedAt: Date?
    public var textState: TextState = .none
    /// The count of passages in index.sqlite.
    public var passages = 0
    /// The kept folder of a file (phase 2, Q6).
    public var parentDocID: Int64?

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
    case item, project, doc, alert, list, settings, mirror, store, flag, calEvent = "cal_event"
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
