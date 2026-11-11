import Foundation

/// index.sqlite (phase 2 build spec, 7.2): the text of kept documents in passages, the keyword index of the
/// passages, and the numbers. All of it can be built again from the kept files and from pa.sqlite, so it has no
/// daily copy. If the file has an error, the PA deletes it and builds it again.
public final class IndexStore {
    public let db: SQLite
    public let url: URL
    let keywords: KeywordIndex
    /// Set if the file had an error and the PA started a new one.
    public private(set) var rebuilt = false

    public static let schemaVersion = 1

    public init(url: URL) throws {
        self.url = url
        var opened: SQLite?
        do {
            let d = try SQLite(path: url.path)
            try Store.check(d)
            opened = d
        } catch {
            opened = nil
        }
        if opened == nil {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
            opened = try SQLite(path: url.path)
            rebuilt = true
        }
        db = opened!
        try db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        try db.exec("""
        CREATE TABLE IF NOT EXISTS passage (
          id INTEGER PRIMARY KEY,
          doc_id INTEGER NOT NULL,
          position INTEGER NOT NULL,
          page INTEGER,
          text TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS passage_doc ON passage(doc_id);
        CREATE TABLE IF NOT EXISTS vector (
          owner_kind TEXT NOT NULL,
          owner_id INTEGER NOT NULL,
          model_id TEXT NOT NULL,
          dimension INTEGER NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY (owner_kind, owner_id)
        );
        PRAGMA user_version = 1;
        """)
        keywords = try KeywordIndex(db: db, table: "passage_fts")
    }

    /// Replaces all passages of a document, in one transaction. Their numbers go too.
    public func replacePassages(doc: Int64, _ passages: [Passage]) throws {
        try db.transaction {
            try deleteRows(doc: doc)
            for p in passages {
                try db.run("INSERT INTO passage(doc_id, position, page, text) VALUES (?, ?, ?, ?)",
                           [.int(doc), .int(Int64(p.position)), p.page.map { .int(Int64($0)) } ?? .null, .text(p.text)])
                try keywords.add(db.lastInsertID, p.text)
            }
        }
    }

    /// Deletes the passages and the numbers of a document at once (R-PA-9).
    public func deleteDoc(_ doc: Int64) throws {
        try db.transaction { try deleteRows(doc: doc) }
    }

    func deleteRows(doc: Int64) throws {
        let ids = try db.query("SELECT id FROM passage WHERE doc_id = ?", [.int(doc)]).compactMap { $0.first?.int }
        for id in ids {
            try keywords.remove(id)
            try db.run("DELETE FROM vector WHERE owner_kind = 'passage' AND owner_id = ?", [.int(id)])
        }
        try db.run("DELETE FROM passage WHERE doc_id = ?", [.int(doc)])
    }

    public struct Row: Equatable, Sendable {
        public var id: Int64
        public var docID: Int64
        public var position: Int
        public var page: Int?
        public var text: String
    }

    static func row(_ r: [SQLValue]) -> Row {
        Row(id: r[0].int ?? 0, docID: r[1].int ?? 0, position: Int(r[2].int ?? 0), page: r[3].int.map { Int($0) },
            text: r[4].text ?? "")
    }

    public func passages(doc: Int64) -> [Row] {
        ((try? db.query("SELECT id, doc_id, position, page, text FROM passage WHERE doc_id = ? ORDER BY position", [.int(doc)])) ?? [])
            .map(IndexStore.row)
    }

    public func passage(_ id: Int64) -> Row? {
        (try? db.query("SELECT id, doc_id, position, page, text FROM passage WHERE id = ?", [.int(id)]))?.first.map(IndexStore.row)
    }

    /// The passages with one or more of the words, best first.
    public func search(_ text: String, limit: Int) -> [Row] {
        keywords.search(text, limit: limit).compactMap(passage)
    }

    public func passageCount() -> Int {
        Int((try? db.query("SELECT COUNT(*) FROM passage"))?.first?.first?.int ?? 0)
    }
}
