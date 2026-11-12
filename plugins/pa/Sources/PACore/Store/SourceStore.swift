import Foundation

// Phase 3 (build spec 7.3): the tables for the calendar, the flags and the seen messages and notes.
// The log table of phase 1 is called `event`, so the calendar table is `cal_event`.

/// The kind of a flag.
public enum FlagKind: String, Sendable {
    /// A mail or a note asks the owner to do something (spec 8.4).
    case request
    /// A mail for a project or for a "waiting for" item (spec 8.7).
    case arrival
}

/// The source of a flag or of a seen record.
public enum SourceKind: String, Sendable, CaseIterable {
    case mail, note, calendar
}

public enum FlagState: String, Sendable {
    case new, kept, dropped, answered
}

/// One flag: a proposal of the PA (R-PA-5). It makes no reminder and no to-do before the owner says "keep".
/// It keeps the sender name, the subject and one sentence. Nothing more of the mail.
public struct Flag: Equatable, Sendable {
    public var id: Int64 = 0
    public var kind: FlagKind
    public var source: SourceKind
    /// The id of the message in Mail, or of the note in Notes.
    public var sourceID: String
    /// The Message-ID header, for the link `message://`.
    public var messageID: String?
    public var sender: String
    /// The subject of the mail or the name of the note.
    public var subject: String
    /// The sentence that the owner must see, as written in the source. Empty for some arrival flags.
    public var sentence: String
    /// The proposed due day ("?" on screen).
    public var dueOn: Day?
    public var projectID: Int64?
    /// "rule" for a proposal, "owner" after the owner set it.
    public var projectBy: String?
    /// A linked item, for example the "waiting for" item of an arrival flag, or the to-do of a kept flag.
    public var itemID: Int64?
    public var state: FlagState = .new
    public var score: Double?
    /// The time of the mail or of the change of the note.
    public var sourceAt: Date
    public var createdAt: Date
    public var answeredAt: Date?

    public init(kind: FlagKind, source: SourceKind, sourceID: String, sender: String, subject: String,
                sentence: String, sourceAt: Date, createdAt: Date) {
        self.kind = kind; self.source = source; self.sourceID = sourceID; self.sender = sender
        self.subject = subject; self.sentence = sentence; self.sourceAt = sourceAt; self.createdAt = createdAt
    }

    /// The address that opens the mail in the Mail app, or nil.
    public var mailLink: String? {
        guard source == .mail, let m = messageID, !m.isEmpty else { return nil }
        var inner = m
        if inner.hasPrefix("<") { inner.removeFirst() }
        if inner.hasSuffix(">") { inner.removeLast() }
        let enc = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "@.-_+=$!")))
            ?? inner
        return "message://%3C" + enc + "%3E"
    }

    /// The subject with no "Re:", "Fwd:" or "Fw:" at the start, in lower case. One open flag for each conversation.
    public static func conversation(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespaces)
        while true {
            let low = s.lowercased()
            guard let p = ["re:", "fwd:", "fw:", "aw:", "wg:"].first(where: { low.hasPrefix($0) }) else { break }
            s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return s.lowercased()
    }
}

/// One calendar event of the next 14 days (spec 7.3). The PA deletes it 1 day after its end.
public struct CalEvent: Equatable, Sendable {
    public var id: Int64 = 0
    /// The id of EventKit.
    public var sourceID: String
    public var title: String
    public var startsAt: Date
    public var endsAt: Date
    public var allDay: Bool
    /// The names of the people of the event.
    public var people: [String]
    public var place: String?

    public init(sourceID: String, title: String, startsAt: Date, endsAt: Date, allDay: Bool = false,
                people: [String] = [], place: String? = nil) {
        self.sourceID = sourceID; self.title = title; self.startsAt = startsAt; self.endsAt = endsAt
        self.allDay = allDay; self.people = people; self.place = place
    }
}

/// A link between a calendar event and an item or a document.
public struct EventLink: Equatable, Sendable {
    public var eventID: Int64
    public var itemID: Int64?
    public var docID: Int64?
    /// "owner" or "rule".
    public var by: String
    public var score: Double?

    public init(eventID: Int64, itemID: Int64? = nil, docID: Int64? = nil, by: String, score: Double? = nil) {
        self.eventID = eventID; self.itemID = itemID; self.docID = docID; self.by = by; self.score = score
    }
}

/// The result of one look at a message or a note. No subject and no sender.
public enum SeenResult: String, Sendable {
    case bulk
    case noRequest = "no_request"
    case flag
    case failed
    /// The read failed or reached the time limit. The PA tries again, 3 times at most.
    case retry
}

extension Store {
    /// Phase 3 (build spec 7.3).
    func migration3() throws {
        try db.transaction {
            try db.exec("""
            CREATE TABLE IF NOT EXISTS cal_event (
              id INTEGER PRIMARY KEY,
              source_id TEXT NOT NULL UNIQUE,
              title TEXT NOT NULL,
              starts_at REAL NOT NULL,
              ends_at REAL NOT NULL,
              all_day INTEGER NOT NULL DEFAULT 0,
              people TEXT NOT NULL DEFAULT '',
              place TEXT
            );
            CREATE INDEX IF NOT EXISTS cal_event_start ON cal_event(starts_at);
            CREATE TABLE IF NOT EXISTS cal_event_link (
              id INTEGER PRIMARY KEY,
              event_id INTEGER NOT NULL,
              item_id INTEGER,
              doc_id INTEGER,
              by TEXT NOT NULL,
              score REAL,
              created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS cal_event_link_event ON cal_event_link(event_id);
            CREATE TABLE IF NOT EXISTS flag (
              id INTEGER PRIMARY KEY,
              kind TEXT NOT NULL,
              source TEXT NOT NULL,
              source_id TEXT NOT NULL,
              message_id TEXT,
              sender TEXT NOT NULL,
              subject TEXT NOT NULL,
              sentence TEXT NOT NULL,
              conversation TEXT NOT NULL,
              due_on TEXT,
              project_id INTEGER,
              project_by TEXT,
              item_id INTEGER,
              state TEXT NOT NULL DEFAULT 'new',
              score REAL,
              source_at REAL NOT NULL,
              created_at REAL NOT NULL,
              answered_at REAL
            );
            CREATE INDEX IF NOT EXISTS flag_state ON flag(state);
            CREATE TABLE IF NOT EXISTS source_seen (
              source TEXT NOT NULL,
              source_id TEXT NOT NULL,
              seen_at REAL NOT NULL,
              result TEXT NOT NULL,
              tries INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (source, source_id)
            );
            PRAGMA user_version = 3;
            """)
        }
    }

    // MARK: - Flags

    static let flagColumns = """
        id, kind, source, source_id, message_id, sender, subject, sentence, due_on, project_id, project_by, item_id,
        state, score, source_at, created_at, answered_at
        """

    static func flag(_ r: [SQLValue]) -> Flag {
        var f = Flag(kind: FlagKind(rawValue: r[1].text ?? "") ?? .request,
                     source: SourceKind(rawValue: r[2].text ?? "") ?? .mail,
                     sourceID: r[3].text ?? "", sender: r[5].text ?? "", subject: r[6].text ?? "",
                     sentence: r[7].text ?? "", sourceAt: date(r[14]) ?? Date(timeIntervalSince1970: 0),
                     createdAt: date(r[15]) ?? Date(timeIntervalSince1970: 0))
        f.id = r[0].int ?? 0
        f.messageID = r[4].text
        f.dueOn = r[8].text.flatMap { Day(text: $0) }
        f.projectID = r[9].int
        f.projectBy = r[10].text
        f.itemID = r[11].int
        f.state = FlagState(rawValue: r[12].text ?? "") ?? .new
        f.score = r[13].real
        f.answeredAt = date(r[16])
        return f
    }

    func flagParams(_ f: Flag) -> [SQLValue] {
        [.text(f.kind.rawValue), .text(f.source.rawValue), .text(f.sourceID), f.messageID.map { .text($0) } ?? .null,
         .text(f.sender), .text(f.subject), .text(f.sentence), .text(Flag.conversation(f.subject)),
         f.dueOn.map { .text($0.description) } ?? .null, f.projectID.map { .int($0) } ?? .null,
         f.projectBy.map { .text($0) } ?? .null, f.itemID.map { .int($0) } ?? .null, .text(f.state.rawValue),
         f.score.map { .real($0) } ?? .null, .real(f.sourceAt.timeIntervalSince1970),
         .real(f.createdAt.timeIntervalSince1970), f.answeredAt.map { .real($0.timeIntervalSince1970) } ?? .null]
    }

    /// Adds a flag. If an open flag of the same kind is there for the same sender and conversation, the PA changes
    /// that flag (spec 8.6: one open flag for one conversation). Gives the id.
    @discardableResult
    public func upsertFlag(_ f: Flag) throws -> Int64 {
        try db.transaction {
            if let old = try db.query("""
                SELECT id FROM flag WHERE state = 'new' AND kind = ? AND source = ? AND sender = ? AND conversation = ?
                ORDER BY id DESC LIMIT 1
                """, [.text(f.kind.rawValue), .text(f.source.rawValue), .text(f.sender),
                      .text(Flag.conversation(f.subject))]).first?.first?.int {
                var g = f
                g.id = old
                try updateFlag(g)
                return old
            }
            try db.run("""
            INSERT INTO flag(kind, source, source_id, message_id, sender, subject, sentence, conversation, due_on,
                             project_id, project_by, item_id, state, score, source_at, created_at, answered_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, flagParams(f))
            let id = db.lastInsertID
            log("flag", .flag, id, at: f.createdAt)
            return id
        }
    }

    public func updateFlag(_ f: Flag) throws {
        try db.run("""
        UPDATE flag SET kind = ?, source = ?, source_id = ?, message_id = ?, sender = ?, subject = ?, sentence = ?,
          conversation = ?, due_on = ?, project_id = ?, project_by = ?, item_id = ?, state = ?, score = ?,
          source_at = ?, created_at = ?, answered_at = ?
        WHERE id = ?
        """, flagParams(f) + [.int(f.id)])
    }

    public func flag(_ id: Int64) -> Flag? {
        (try? db.query("SELECT \(Store.flagColumns) FROM flag WHERE id = ?", [.int(id)]))?.first.map(Store.flag)
    }

    /// The open flags, newest first.
    public func openFlags(kind: FlagKind? = nil) -> [Flag] {
        var sql = "SELECT \(Store.flagColumns) FROM flag WHERE state = 'new'"
        var params: [SQLValue] = []
        if let kind { sql += " AND kind = ?"; params.append(.text(kind.rawValue)) }
        sql += " ORDER BY source_at DESC, id DESC"
        return ((try? db.query(sql, params)) ?? []).map(Store.flag)
    }

    /// The count of flags of each state that the owner answered since the time (for the Today page).
    public func flagAnswers(since: Date) -> [String: Int] {
        let rows = (try? db.query("SELECT state, COUNT(*) FROM flag WHERE answered_at >= ? GROUP BY state",
                                  [.real(since.timeIntervalSince1970)])) ?? []
        var out: [String: Int] = [:]
        for r in rows { if let t = r[0].text, let n = r[1].int { out[t] = Int(n) } }
        return out
    }

    /// Rule 4 of 7.3: the subject and the sentence of a kept or dropped flag go 30 days after the answer.
    public func forgetOldFlagText(now: Date) throws {
        let cut = now.addingTimeInterval(-30 * 86400).timeIntervalSince1970
        try db.run("""
        UPDATE flag SET subject = '', sentence = '' WHERE state IN ('kept', 'dropped', 'answered')
          AND answered_at IS NOT NULL AND answered_at < ? AND (subject != '' OR sentence != '')
        """, [.real(cut)])
    }

    // MARK: - Seen records

    /// The result of the last look at a message or a note, with the count of tries.
    public func seen(_ source: SourceKind, _ id: String) -> (result: SeenResult, tries: Int)? {
        guard let r = (try? db.query("SELECT result, tries FROM source_seen WHERE source = ? AND source_id = ?",
                                     [.text(source.rawValue), .text(id)]))?.first else { return nil }
        return (SeenResult(rawValue: r[0].text ?? "") ?? .failed, Int(r[1].int ?? 0))
    }

    /// Records a look. A `.retry` adds one to the tries. After 3 tries it becomes `.failed` (spec 7.4).
    public func markSeen(_ source: SourceKind, _ id: String, _ result: SeenResult, at: Date) throws {
        var res = result
        var tries = 0
        if result == .retry {
            tries = (seen(source, id)?.tries ?? 0) + 1
            if tries >= 3 { res = .failed }
        }
        try db.run("INSERT OR REPLACE INTO source_seen(source, source_id, seen_at, result, tries) VALUES (?, ?, ?, ?, ?)",
                   [.text(source.rawValue), .text(id), .real(at.timeIntervalSince1970), .text(res.rawValue), .int(Int64(tries))])
    }

    /// Deletes all that the PA kept from a source, at once (setting `sources`, spec 7.2).
    public func forgetSource(_ source: SourceKind) throws {
        try db.transaction {
            switch source {
            case .calendar:
                try db.exec("DELETE FROM cal_event_link; DELETE FROM cal_event;")
            case .mail, .note:
                try db.run("DELETE FROM flag WHERE source = ? AND state = 'new'", [.text(source.rawValue)])
                // An answered flag keeps its row for the counts, with no text.
                try db.run("UPDATE flag SET subject = '', sentence = '', sender = '' WHERE source = ?", [.text(source.rawValue)])
            }
            try db.run("DELETE FROM source_seen WHERE source = ?", [.text(source.rawValue)])
        }
    }

    // MARK: - Calendar events

    static let calEventColumns = "id, source_id, title, starts_at, ends_at, all_day, people, place"

    static func calEvent(_ r: [SQLValue]) -> CalEvent {
        var e = CalEvent(sourceID: r[1].text ?? "", title: r[2].text ?? "",
                         startsAt: date(r[3]) ?? Date(timeIntervalSince1970: 0),
                         endsAt: date(r[4]) ?? Date(timeIntervalSince1970: 0), allDay: (r[5].int ?? 0) != 0,
                         people: (r[6].text ?? "").split(separator: "\n").map(String.init), place: r[7].text)
        e.id = r[0].int ?? 0
        return e
    }

    /// Adds or changes an event by its EventKit id. Gives the row id.
    @discardableResult
    public func upsertEvent(_ e: CalEvent) throws -> Int64 {
        try db.run("""
        INSERT INTO cal_event(source_id, title, starts_at, ends_at, all_day, people, place) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_id) DO UPDATE SET title = excluded.title, starts_at = excluded.starts_at,
          ends_at = excluded.ends_at, all_day = excluded.all_day, people = excluded.people, place = excluded.place
        """, [.text(e.sourceID), .text(e.title), .real(e.startsAt.timeIntervalSince1970),
              .real(e.endsAt.timeIntervalSince1970), .int(e.allDay ? 1 : 0), .text(e.people.joined(separator: "\n")),
              e.place.map { .text($0) } ?? .null])
        return try db.query("SELECT id FROM cal_event WHERE source_id = ?", [.text(e.sourceID)]).first?.first?.int ?? 0
    }

    /// The events that start in the span, by start time.
    public func events(from: Date, to: Date) -> [CalEvent] {
        ((try? db.query("SELECT \(Store.calEventColumns) FROM cal_event WHERE starts_at >= ? AND starts_at < ? ORDER BY starts_at",
                        [.real(from.timeIntervalSince1970), .real(to.timeIntervalSince1970)])) ?? []).map(Store.calEvent)
    }

    /// Deletes the events that ended more than 1 day ago, and the events that are not in the source any more.
    public func pruneEvents(now: Date, keep ids: Set<String>? = nil, readFrom: Date? = nil) throws {
        try db.transaction {
            let cut = now.addingTimeInterval(-86400).timeIntervalSince1970
            try db.run("DELETE FROM cal_event_link WHERE event_id IN (SELECT id FROM cal_event WHERE ends_at < ?)", [.real(cut)])
            try db.run("DELETE FROM cal_event WHERE ends_at < ?", [.real(cut)])
            if let ids, let readFrom {
                let rows = try db.query("SELECT id, source_id FROM cal_event WHERE starts_at >= ?", [.real(readFrom.timeIntervalSince1970)])
                for r in rows where !ids.contains(r[1].text ?? "") {
                    try db.run("DELETE FROM cal_event_link WHERE event_id = ?", [r[0]])
                    try db.run("DELETE FROM cal_event WHERE id = ?", [r[0]])
                }
            }
        }
    }

    public func addEventLink(_ l: EventLink, at: Date) throws {
        try db.run("INSERT INTO cal_event_link(event_id, item_id, doc_id, by, score, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                   [.int(l.eventID), l.itemID.map { .int($0) } ?? .null, l.docID.map { .int($0) } ?? .null,
                    .text(l.by), l.score.map { .real($0) } ?? .null, .real(at.timeIntervalSince1970)])
    }

    /// The near-event alerts shown since the time, and how many of them got an answer: a change to a linked item in
    /// the hour after the alert (done, snooze, drop, move or another change).
    public func eventAlertAnswers(since: Date) -> (shown: Int, answered: Int) {
        let s = since.timeIntervalSince1970
        let shown = (try? db.query("SELECT COUNT(*) FROM event WHERE type = 'alert-shown' AND record_kind = 'cal_event' AND at >= ?",
                                   [.real(s)]))?.first?.first?.int ?? 0
        let answered = (try? db.query("""
            SELECT COUNT(DISTINCT a.id) FROM event a
            JOIN cal_event_link l ON l.event_id = a.record_id AND l.item_id IS NOT NULL
            JOIN event b ON b.record_kind = 'item' AND b.record_id = l.item_id AND b.at >= a.at AND b.at <= a.at + 3600
              AND b.type IN ('done', 'snooze', 'drop', 'move', 'change')
            WHERE a.type = 'alert-shown' AND a.record_kind = 'cal_event' AND a.at >= ?
            """, [.real(s)]))?.first?.first?.int ?? 0
        return (Int(shown), Int(answered))
    }

    /// Deletes the links by a rule of an event. The links by the owner stay.
    public func deleteRuleLinks(_ eventID: Int64) throws {
        try db.run("DELETE FROM cal_event_link WHERE event_id = ? AND by = 'rule'", [.int(eventID)])
    }

    public func eventLinks(_ eventID: Int64) -> [EventLink] {
        ((try? db.query("SELECT event_id, item_id, doc_id, by, score FROM cal_event_link WHERE event_id = ? ORDER BY id",
                        [.int(eventID)])) ?? []).map {
            EventLink(eventID: $0[0].int ?? 0, itemID: $0[1].int, docID: $0[2].int, by: $0[3].text ?? "rule", score: $0[4].real)
        }
    }
}
