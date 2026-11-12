import Foundation

/// The kind of full-text search that the system SQLite supports. Probe 3 of the build decides it at each start.
public enum SearchIndexKind: String, Sendable {
    case fts5, fts4
    /// No full-text module: a plain table and LIKE.
    case like
}

/// The store: one SQLite file, pa.sqlite, in the data folder (R-PA-1). One serial queue owns it. One writer.
public final class Store {
    public let db: SQLite
    public let url: URL
    public private(set) var searchKind: SearchIndexKind = .like
    /// Set if the store file did not open and the PA started a new one. The next answer tells the owner.
    public private(set) var recoveredFrom: URL?

    /// The schema version. Each change is one numbered migration.
    public static let schemaVersion = 3

    public init(url: URL, now: Date = Date()) throws {
        self.url = url
        var opened: SQLite?
        do {
            let first = try SQLite(path: url.path)
            try Store.check(first)
            opened = first
        } catch {
            opened = nil
        }
        if let opened {
            db = opened
        } else {
            // The file does not open: keep it as pa-broken-<time>.sqlite and start a new one.
            let stamp = Int(now.timeIntervalSince1970)
            let broken = url.deletingLastPathComponent().appendingPathComponent("pa-broken-\(stamp).sqlite")
            try? FileManager.default.moveItem(at: url, to: broken)
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
            db = try SQLite(path: url.path)
            recoveredFrom = broken
        }
        try db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;")
        try migrate()
        searchKind = SearchIndexKind(rawValue: meta("search_index") ?? "") ?? .like
    }

    /// Reads the file header and the schema. Throws if the file is not a SQLite database.
    static func check(_ db: SQLite) throws {
        let rows = try db.query("PRAGMA quick_check")
        guard rows.first?.first?.text == "ok" else { throw SQLError(code: 11, message: "quick_check failed") }
    }

    public func clearRecovered() { recoveredFrom = nil }

    // MARK: - Migrations

    func migrate() throws {
        let version = try db.query("PRAGMA user_version").first?.first?.int ?? 0
        if version < 1 { try migration1() }
        if version < 2 { try migration2() }
        if version < 3 { try migration3() }
    }

    /// Phase 2 (build spec 7.2): kept files, proposals of the search, closed projects.
    func migration2() throws {
        try db.transaction {
            let cols: [(String, String)] = [
                ("doc", "path TEXT"), ("doc", "kind TEXT NOT NULL DEFAULT 'page'"), ("doc", "size INTEGER"),
                ("doc", "modified_at REAL"), ("doc", "text_state TEXT NOT NULL DEFAULT 'none'"),
                ("doc", "passages INTEGER NOT NULL DEFAULT 0"), ("doc", "parent_doc_id INTEGER"),
                ("item", "project_by TEXT"), ("item", "project_score REAL"),
                ("project", "closed_at REAL"),
            ]
            for (table, col) in cols {
                let name = String(col.prefix { $0 != " " })
                let have = try db.query("PRAGMA table_info(\(table))").contains { $0[1].text == name }
                if !have { try db.exec("ALTER TABLE \(table) ADD COLUMN \(col)") }
            }
            // A project with an item set by the owner keeps "owner".
            try db.exec("UPDATE item SET project_by = 'owner' WHERE project_id IS NOT NULL AND project_by IS NULL")
            try db.exec("PRAGMA user_version = 2")
        }
    }

    func migration1() throws {
        try db.transaction {
            try db.exec("""
            CREATE TABLE IF NOT EXISTS item (
              id INTEGER PRIMARY KEY,
              kind TEXT NOT NULL,
              said TEXT NOT NULL,
              title TEXT NOT NULL,
              state TEXT NOT NULL DEFAULT 'open',
              remind_at REAL,
              due_on TEXT,
              has_clock INTEGER NOT NULL DEFAULT 0,
              project_id INTEGER,
              doc_id INTEGER,
              context_app TEXT,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              done_at REAL,
              dropped_at REAL
            );
            CREATE INDEX IF NOT EXISTS item_state ON item(state);
            CREATE TABLE IF NOT EXISTS project (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              slug TEXT NOT NULL UNIQUE,
              state TEXT NOT NULL DEFAULT 'open',
              created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS project_alias (
              project_id INTEGER NOT NULL,
              name TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS doc (
              id INTEGER PRIMARY KEY,
              address TEXT,
              title TEXT NOT NULL,
              app TEXT,
              project_id INTEGER,
              created_at REAL NOT NULL,
              dropped_at REAL
            );
            CREATE TABLE IF NOT EXISTS alert (
              id INTEGER PRIMARY KEY,
              item_id INTEGER,
              rule TEXT NOT NULL,
              fire_at REAL NOT NULL,
              state TEXT NOT NULL DEFAULT 'planned',
              shown_at REAL
            );
            CREATE INDEX IF NOT EXISTS alert_fire ON alert(state, fire_at);
            CREATE TABLE IF NOT EXISTS last_list (
              position INTEGER PRIMARY KEY,
              record_kind TEXT NOT NULL,
              record_id INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS mirror (
              item_id INTEGER PRIMARY KEY,
              reminder_id TEXT NOT NULL UNIQUE,
              synced_print TEXT NOT NULL,
              synced_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS event (
              id INTEGER PRIMARY KEY,
              at REAL NOT NULL,
              type TEXT NOT NULL,
              record_kind TEXT,
              record_id INTEGER
            );
            CREATE INDEX IF NOT EXISTS event_at ON event(at);
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY,
              value TEXT
            );
            """)
            // Probe 3: the full-text search of the system SQLite. FTS5, then FTS4, then LIKE.
            var kind = SearchIndexKind.like
            do {
                try db.exec("CREATE VIRTUAL TABLE IF NOT EXISTS item_fts USING fts5(body, tokenize='unicode61 remove_diacritics 2')")
                kind = .fts5
            } catch {
                do {
                    try db.exec("CREATE VIRTUAL TABLE IF NOT EXISTS item_fts USING fts4(body)")
                    kind = .fts4
                } catch {
                    try db.exec("CREATE TABLE IF NOT EXISTS item_fts (rowid INTEGER PRIMARY KEY, body TEXT)")
                    kind = .like
                }
            }
            try db.run("INSERT OR REPLACE INTO meta(key, value) VALUES ('search_index', ?)", [.text(kind.rawValue)])
            try db.exec("PRAGMA user_version = 1")
        }
    }

    // MARK: - Meta

    public func meta(_ key: String) -> String? {
        (try? db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]))?.first?.first?.text
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try db.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", [.text(key), .text(value)])
        } else {
            try db.run("DELETE FROM meta WHERE key = ?", [.text(key)])
        }
    }

    // MARK: - Events (no text: times, types and record numbers only)

    public func log(_ type: String, _ kind: RecordKind? = nil, _ id: Int64? = nil, at: Date) {
        _ = try? db.run("INSERT INTO event(at, type, record_kind, record_id) VALUES (?, ?, ?, ?)",
                        [.real(at.timeIntervalSince1970), .text(type), kind.map { .text($0.rawValue) } ?? .null,
                         id.map { .int($0) } ?? .null])
    }

    /// The count of each event type since the time.
    public func eventCounts(since: Date) -> [String: Int] {
        let rows = (try? db.query("SELECT type, COUNT(*) FROM event WHERE at >= ? GROUP BY type",
                                  [.real(since.timeIntervalSince1970)])) ?? []
        var out: [String: Int] = [:]
        for r in rows { if let t = r[0].text, let n = r[1].int { out[t] = Int(n) } }
        return out
    }

    /// The last event of a type, with its record.
    public func lastEvent(_ types: [String]) -> (at: Date, kind: RecordKind?, id: Int64?)? {
        let marks = types.map { _ in "?" }.joined(separator: ",")
        guard let r = (try? db.query("SELECT at, record_kind, record_id FROM event WHERE type IN (\(marks)) ORDER BY id DESC LIMIT 1",
                                     types.map { .text($0) }))?.first else { return nil }
        return (Date(timeIntervalSince1970: r[0].real ?? 0), r[1].text.flatMap(RecordKind.init(rawValue:)), r[2].int)
    }

    // MARK: - Search index

    /// The rowid of a record in the search index: the record id and its kind in one number.
    static func searchRowID(_ kind: RecordKind, _ id: Int64) -> Int64 {
        let k: Int64 = kind == .item ? 1 : (kind == .doc ? 2 : 3)
        return id * 4 + k
    }

    static func record(searchRowID r: Int64) -> (RecordKind, Int64) {
        let k = r % 4
        return (k == 1 ? .item : (k == 2 ? .doc : .project), r / 4)
    }

    func index(_ kind: RecordKind, _ id: Int64, _ body: String?) throws {
        let rowid = Store.searchRowID(kind, id)
        try db.run("DELETE FROM item_fts WHERE rowid = ?", [.int(rowid)])
        if let body, !body.isEmpty {
            try db.run("INSERT INTO item_fts(rowid, body) VALUES (?, ?)", [.int(rowid), .text(body)])
        }
    }

    /// The records that have all the words, best first.
    public func search(_ words: [String], limit: Int) -> [(RecordKind, Int64)] {
        let clean = words.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return [] }
        let rows: [[SQLValue]]
        switch searchKind {
        case .fts5:
            let q = clean.map { "\"\($0)\"*" }.joined(separator: " AND ")
            rows = (try? db.query("SELECT rowid FROM item_fts WHERE item_fts MATCH ? ORDER BY rank LIMIT ?",
                                  [.text(q), .int(Int64(limit))])) ?? []
        case .fts4:
            let q = clean.map { "\($0)*" }.joined(separator: " ")
            rows = (try? db.query("SELECT rowid FROM item_fts WHERE item_fts MATCH ? ORDER BY rowid DESC LIMIT ?",
                                  [.text(q), .int(Int64(limit))])) ?? []
        case .like:
            let cond = clean.map { _ in "lower(body) LIKE ?" }.joined(separator: " AND ")
            rows = (try? db.query("SELECT rowid FROM item_fts WHERE \(cond) ORDER BY rowid DESC LIMIT ?",
                                  clean.map { .text("%\($0)%") } + [.int(Int64(limit))])) ?? []
        }
        return rows.compactMap { $0.first?.int }.map(Store.record(searchRowID:))
    }

    // MARK: - Items

    static let itemColumns = "id, kind, said, title, state, remind_at, due_on, has_clock, project_id, doc_id, context_app, created_at, updated_at, done_at, dropped_at, project_by, project_score"

    static func date(_ v: SQLValue) -> Date? { v.real.map { Date(timeIntervalSince1970: $0) } }
    static func value(_ d: Date?) -> SQLValue { d.map { .real($0.timeIntervalSince1970) } ?? .null }
    static func value(_ i: Int64?) -> SQLValue { i.map { .int($0) } ?? .null }
    static func value(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }

    static func item(_ r: [SQLValue]) -> Item {
        var it = Item(kind: ItemKind(rawValue: r[1].text ?? "") ?? .todo, said: r[2].text ?? "", title: r[3].text ?? "",
                      createdAt: date(r[11]) ?? Date(timeIntervalSince1970: 0))
        it.id = r[0].int ?? 0
        it.state = ItemState(rawValue: r[4].text ?? "") ?? .open
        it.remindAt = date(r[5])
        it.dueOn = r[6].text.flatMap(Day.init(text:))
        it.hasClock = (r[7].int ?? 0) != 0
        it.projectID = r[8].int
        it.docID = r[9].int
        it.contextApp = r[10].text
        it.updatedAt = date(r[12]) ?? it.createdAt
        it.doneAt = date(r[13])
        if r.count > 16 {
            it.projectBy = r[15].text
            it.projectScore = r[16].real
        }
        it.droppedAt = date(r[14])
        return it
    }

    func itemParams(_ it: Item) -> [SQLValue] {
        [.text(it.kind.rawValue), .text(it.said), .text(it.title), .text(it.state.rawValue), Store.value(it.remindAt),
         Store.value(it.dueOn?.description), .int(it.hasClock ? 1 : 0), Store.value(it.projectID), Store.value(it.docID),
         Store.value(it.contextApp), .real(it.createdAt.timeIntervalSince1970), .real(it.updatedAt.timeIntervalSince1970),
         Store.value(it.doneAt), Store.value(it.droppedAt), Store.value(it.projectBy), it.projectScore.map { .real($0) } ?? .null]
    }

    /// Saves a new item, its search entry and its event in one transaction. Gives the id.
    @discardableResult
    public func insert(_ it: Item, event: String = "capture") throws -> Int64 {
        try db.transaction {
            try db.run("""
            INSERT INTO item(kind, said, title, state, remind_at, due_on, has_clock, project_id, doc_id, context_app,
                             created_at, updated_at, done_at, dropped_at, project_by, project_score)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, itemParams(it))
            let id = db.lastInsertID
            try index(.item, id, it.state == .dropped ? nil : it.title + " " + it.said)
            log(event, .item, id, at: it.createdAt)
            return id
        }
    }

    /// Saves a change of an item, its search entry and its event in one transaction.
    public func update(_ it: Item, event: String, at: Date) throws {
        try db.transaction {
            var p = itemParams(it)
            p.append(.int(it.id))
            try db.run("""
            UPDATE item SET kind = ?, said = ?, title = ?, state = ?, remind_at = ?, due_on = ?, has_clock = ?,
              project_id = ?, doc_id = ?, context_app = ?, created_at = ?, updated_at = ?, done_at = ?, dropped_at = ?,
              project_by = ?, project_score = ?
            WHERE id = ?
            """, p)
            try index(.item, it.id, it.state == .dropped ? nil : it.title + " " + it.said)
            log(event, .item, it.id, at: at)
        }
    }

    public func item(_ id: Int64) -> Item? {
        (try? db.query("SELECT \(Store.itemColumns) FROM item WHERE id = ?", [.int(id)]))?.first.map(Store.item)
    }

    /// Items by a SQL condition on the item table.
    public func items(where cond: String, _ params: [SQLValue] = [], order: String = "id") -> [Item] {
        ((try? db.query("SELECT \(Store.itemColumns) FROM item WHERE \(cond) ORDER BY \(order)", params)) ?? []).map(Store.item)
    }

    public func openItems() -> [Item] { items(where: "state = 'open'") }

    /// The count of items in the store, of all states.
    public func itemCount() -> Int { Int((try? db.query("SELECT COUNT(*) FROM item"))?.first?.first?.int ?? 0) }

    // MARK: - Projects

    public static func key(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func slug(_ s: String) -> String {
        let parts = s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let out = parts.joined(separator: "-")
        return out.isEmpty ? "project" : out
    }

    public func insertProject(_ name: String, at: Date) throws -> Project {
        try db.transaction {
            var slug = Store.slug(name)
            var n = 2
            while (try db.query("SELECT 1 FROM project WHERE slug = ?", [.text(slug)])).first != nil {
                slug = Store.slug(name) + "-\(n)"; n += 1
            }
            try db.run("INSERT INTO project(name, slug, state, created_at) VALUES (?, ?, 'open', ?)",
                       [.text(name), .text(slug), .real(at.timeIntervalSince1970)])
            var p = Project(name: name, slug: slug, createdAt: at)
            p.id = db.lastInsertID
            try index(.project, p.id, name)
            log("project", .project, p.id, at: at)
            return p
        }
    }

    public func addAlias(_ projectID: Int64, _ name: String) throws {
        try db.run("INSERT INTO project_alias(project_id, name) VALUES (?, ?)", [.int(projectID), .text(name)])
    }

    public func projects(openOnly: Bool = true) -> [Project] {
        let rows = (try? db.query("SELECT id, name, slug, state, created_at, closed_at FROM project \(openOnly ? "WHERE state = 'open'" : "") ORDER BY name COLLATE NOCASE")) ?? []
        let aliasRows = (try? db.query("SELECT project_id, name FROM project_alias")) ?? []
        var aliases: [Int64: [String]] = [:]
        for a in aliasRows { if let id = a[0].int, let n = a[1].text { aliases[id, default: []].append(n) } }
        return rows.map { r in
            var p = Project(name: r[1].text ?? "", slug: r[2].text ?? "", createdAt: Store.date(r[4]) ?? Date(timeIntervalSince1970: 0))
            p.id = r[0].int ?? 0
            p.state = r[3].text ?? "open"
            p.closedAt = Store.date(r[5])
            p.aliases = aliases[p.id] ?? []
            return p
        }
    }

    public func project(_ id: Int64) -> Project? { projects(openOnly: false).first { $0.id == id } }

    /// The open project whose name or alias has this key (lower case, no spaces and no hyphens).
    public func project(named words: String, includeClosed: Bool = false) -> Project? {
        let k = Store.key(words)
        guard !k.isEmpty else { return nil }
        return projects(openOnly: !includeClosed).first { p in Store.key(p.name) == k || p.aliases.contains { Store.key($0) == k } }
    }

    /// "finish project" (closed) and "new project" for a closed project (open).
    public func setProjectState(_ id: Int64, open: Bool, at: Date) throws {
        try db.transaction {
            try db.run("UPDATE project SET state = ?, closed_at = ? WHERE id = ?",
                       [.text(open ? "open" : "closed"), open ? .null : .real(at.timeIntervalSince1970), .int(id)])
            try index(.project, id, open ? project(id)?.name : nil)
            log(open ? "project-open" : "project-close", .project, id, at: at)
        }
    }

    /// The count of open items of each project.
    public func openCounts() -> [Int64: Int] {
        let rows = (try? db.query("SELECT project_id, COUNT(*) FROM item WHERE state = 'open' AND project_id IS NOT NULL GROUP BY project_id")) ?? []
        var out: [Int64: Int] = [:]
        for r in rows { if let p = r[0].int, let n = r[1].int { out[p] = Int(n) } }
        return out
    }

    // MARK: - Documents

    static let docColumns = "id, address, title, app, project_id, created_at, dropped_at, path, kind, size, modified_at, text_state, passages, parent_doc_id"

    func docParams(_ d: Doc) -> [SQLValue] {
        [Store.value(d.address), .text(d.title), Store.value(d.app), Store.value(d.projectID),
         .real(d.createdAt.timeIntervalSince1970), Store.value(d.droppedAt), Store.value(d.path), .text(d.kind.rawValue),
         Store.value(d.size), Store.value(d.modifiedAt), .text(d.textState.rawValue), .int(Int64(d.passages)),
         Store.value(d.parentDocID)]
    }

    /// The words of a reference in the keyword index of pa.sqlite: the title and the address, not the path.
    static func docBody(_ d: Doc) -> String? {
        d.droppedAt == nil ? d.title + " " + (d.address ?? "") : nil
    }

    public func insertDoc(_ d: Doc) throws -> Int64 {
        try db.transaction {
            try db.run("""
            INSERT INTO doc(address, title, app, project_id, created_at, dropped_at, path, kind, size, modified_at,
                            text_state, passages, parent_doc_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, docParams(d))
            let id = db.lastInsertID
            try index(.doc, id, Store.docBody(d))
            log("keep", .doc, id, at: d.createdAt)
            return id
        }
    }

    static func doc(_ r: [SQLValue]) -> Doc {
        var d = Doc(address: r[1].text, title: r[2].text ?? "", app: r[3].text, projectID: r[4].int,
                    createdAt: date(r[5]) ?? Date(timeIntervalSince1970: 0))
        d.id = r[0].int ?? 0
        d.droppedAt = date(r[6])
        if r.count > 13 {
            d.path = r[7].text
            d.kind = DocKind(rawValue: r[8].text ?? "") ?? .page
            d.size = r[9].int
            d.modifiedAt = date(r[10])
            d.textState = TextState(rawValue: r[11].text ?? "") ?? .none
            d.passages = Int(r[12].int ?? 0)
            d.parentDocID = r[13].int
        }
        return d
    }

    public func doc(_ id: Int64) -> Doc? {
        (try? db.query("SELECT \(Store.docColumns) FROM doc WHERE id = ?", [.int(id)]))?.first.map(Store.doc)
    }

    /// The kept references that are not dropped, of one project or of all.
    public func docs(project: Int64?) -> [Doc] {
        if let project { return docs(where: "dropped_at IS NULL AND project_id = ?", [.int(project)]) }
        return docs(where: "dropped_at IS NULL")
    }

    public func docs(where cond: String, _ params: [SQLValue] = []) -> [Doc] {
        ((try? db.query("SELECT \(Store.docColumns) FROM doc WHERE \(cond) ORDER BY id", params)) ?? []).map(Store.doc)
    }

    /// The kept file with this path that is not dropped.
    public func doc(path: String) -> Doc? {
        docs(where: "dropped_at IS NULL AND path = ?", [.text(path)]).first
    }

    public func updateDoc(_ d: Doc, event: String, at: Date) throws {
        try db.transaction {
            var p = docParams(d)
            p.append(.int(d.id))
            try db.run("""
            UPDATE doc SET address = ?, title = ?, app = ?, project_id = ?, created_at = ?, dropped_at = ?, path = ?,
              kind = ?, size = ?, modified_at = ?, text_state = ?, passages = ?, parent_doc_id = ?
            WHERE id = ?
            """, p)
            try index(.doc, d.id, Store.docBody(d))
            log(event, .doc, d.id, at: at)
        }
    }

    // MARK: - Alerts

    static func alert(_ r: [SQLValue]) -> PlannedAlert {
        var a = PlannedAlert(itemID: r[1].int, rule: r[2].text ?? "", fireAt: date(r[3]) ?? Date(timeIntervalSince1970: 0))
        a.id = r[0].int ?? 0
        a.state = AlertState(rawValue: r[4].text ?? "") ?? .planned
        a.shownAt = date(r[5])
        return a
    }

    @discardableResult
    public func insertAlert(_ a: PlannedAlert) throws -> Int64 {
        try db.run("INSERT INTO alert(item_id, rule, fire_at, state, shown_at) VALUES (?, ?, ?, ?, ?)",
                   [Store.value(a.itemID), .text(a.rule), .real(a.fireAt.timeIntervalSince1970), .text(a.state.rawValue),
                    Store.value(a.shownAt)])
        return db.lastInsertID
    }

    public func updateAlert(_ a: PlannedAlert) throws {
        try db.run("UPDATE alert SET item_id = ?, rule = ?, fire_at = ?, state = ?, shown_at = ? WHERE id = ?",
                   [Store.value(a.itemID), .text(a.rule), .real(a.fireAt.timeIntervalSince1970), .text(a.state.rawValue),
                    Store.value(a.shownAt), .int(a.id)])
    }

    public func alerts(where cond: String, _ params: [SQLValue] = [], order: String = "fire_at") -> [PlannedAlert] {
        ((try? db.query("SELECT id, item_id, rule, fire_at, state, shown_at FROM alert WHERE \(cond) ORDER BY \(order)", params)) ?? [])
            .map(Store.alert)
    }

    // MARK: - The last list

    public func setLastList(_ records: [(RecordKind, Int64)]) throws {
        try db.transaction {
            try db.run("DELETE FROM last_list")
            for (i, r) in records.enumerated() {
                try db.run("INSERT INTO last_list(position, record_kind, record_id) VALUES (?, ?, ?)",
                           [.int(Int64(i + 1)), .text(r.0.rawValue), .int(r.1)])
            }
        }
    }

    public func lastList(_ position: Int) -> (RecordKind, Int64)? {
        guard let r = (try? db.query("SELECT record_kind, record_id FROM last_list WHERE position = ?", [.int(Int64(position))]))?.first,
              let k = r[0].text.flatMap(RecordKind.init(rawValue:)), let id = r[1].int else { return nil }
        return (k, id)
    }

    // MARK: - Mirror

    public func mirrors() -> [MirrorRow] {
        ((try? db.query("SELECT item_id, reminder_id, synced_print, synced_at FROM mirror")) ?? []).compactMap { r in
            guard let i = r[0].int, let rid = r[1].text else { return nil }
            return MirrorRow(itemID: i, reminderID: rid, syncedPrint: r[2].text ?? "", syncedAt: Store.date(r[3]) ?? Date(timeIntervalSince1970: 0))
        }
    }

    public func setMirror(_ m: MirrorRow) throws {
        try db.run("INSERT OR REPLACE INTO mirror(item_id, reminder_id, synced_print, synced_at) VALUES (?, ?, ?, ?)",
                   [.int(m.itemID), .text(m.reminderID), .text(m.syncedPrint), .real(m.syncedAt.timeIntervalSince1970)])
    }

    public func removeMirror(itemID: Int64) throws {
        try db.run("DELETE FROM mirror WHERE item_id = ?", [.int(itemID)])
    }

    // MARK: - Care

    /// Deletes the records that were dropped before the time.
    public func purgeDropped(before: Date) throws {
        try db.transaction {
            let t = SQLValue.real(before.timeIntervalSince1970)
            let ids = try db.query("SELECT id FROM item WHERE state = 'dropped' AND dropped_at < ?", [t]).compactMap { $0.first?.int }
            for id in ids {
                try index(.item, id, nil)
                try db.run("DELETE FROM item WHERE id = ?", [.int(id)])
                try db.run("DELETE FROM alert WHERE item_id = ?", [.int(id)])
            }
            let docs = try db.query("SELECT id FROM doc WHERE dropped_at IS NOT NULL AND dropped_at < ?", [t]).compactMap { $0.first?.int }
            for id in docs {
                try index(.doc, id, nil)
                try db.run("DELETE FROM doc WHERE id = ?", [.int(id)])
            }
        }
    }

    /// Makes the daily copy in backups/ with VACUUM INTO, if no copy of this day exists. Keeps `keep` copies.
    public func backup(folder: URL, day: Day, keep: Int) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("pa-\(day).sqlite")
        if !fm.fileExists(atPath: target.path) {
            try db.run("VACUUM INTO ?", [.text(target.path)])
        }
        let copies = (try fm.contentsOfDirectory(atPath: folder.path)).filter { $0.hasPrefix("pa-") && $0.hasSuffix(".sqlite") }.sorted()
        if copies.count > keep {
            for name in copies.prefix(copies.count - keep) { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
        }
    }
}
