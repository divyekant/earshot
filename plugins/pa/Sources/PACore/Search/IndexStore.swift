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

    // MARK: - Numbers (Q3, build spec 7.6)

    /// The kinds of owner of a list of numbers.
    public enum VectorKind: String, Sendable {
        case passage, item, project
    }

    static func blob(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }

    static func floats(_ d: Data) -> [Float] {
        var out = [Float](repeating: 0, count: d.count / MemoryLayout<Float>.size)
        _ = out.withUnsafeMutableBytes { d.copyBytes(to: $0) }
        return out
    }

    /// Saves lists of numbers, in one transaction. A list for the same owner replaces the old one.
    public func putVectors(_ kind: VectorKind, _ rows: [(Int64, [Float])], model: String) throws {
        try db.transaction {
            for (id, v) in rows {
                try db.run("INSERT OR REPLACE INTO vector(owner_kind, owner_id, model_id, dimension, data) VALUES (?, ?, ?, ?, ?)",
                           [.text(kind.rawValue), .int(id), .text(model), .int(Int64(v.count)), .blob(IndexStore.blob(v))])
            }
        }
    }

    /// All lists of one kind for one model.
    public func vectors(_ kind: VectorKind, model: String) -> [(Int64, [Float])] {
        ((try? db.query("SELECT owner_id, data FROM vector WHERE owner_kind = ? AND model_id = ?",
                        [.text(kind.rawValue), .text(model)])) ?? [])
            .compactMap { r in r[1].blob.map { (r[0].int ?? 0, IndexStore.floats($0)) } }
    }

    /// The owners of one kind that have numbers of the model.
    public func vectorOwners(_ kind: VectorKind, model: String) -> Set<Int64> {
        Set(((try? db.query("SELECT owner_id FROM vector WHERE owner_kind = ? AND model_id = ?",
                            [.text(kind.rawValue), .text(model)])) ?? []).compactMap { $0.first?.int })
    }

    public func deleteVector(_ kind: VectorKind, _ id: Int64) throws {
        try db.run("DELETE FROM vector WHERE owner_kind = ? AND owner_id = ?", [.text(kind.rawValue), .int(id)])
    }

    /// A change of the model: the numbers of other models go, and the index builds them again (7.6).
    @discardableResult
    public func deleteVectors(notOf model: String) throws -> Int {
        try db.run("DELETE FROM vector WHERE model_id != ?", [.text(model)])
    }

    /// Passages with no numbers of the model, in the order of their id.
    public func passagesWithoutVectors(model: String, limit: Int) -> [Row] {
        ((try? db.query("""
            SELECT p.id, p.doc_id, p.position, p.page, p.text FROM passage p
            WHERE NOT EXISTS (SELECT 1 FROM vector v WHERE v.owner_kind = 'passage' AND v.owner_id = p.id AND v.model_id = ?)
            ORDER BY p.id LIMIT ?
            """, [.text(model), .int(Int64(limit))])) ?? []).map(IndexStore.row)
    }

    public func vectorCount(model: String) -> Int {
        Int((try? db.query("SELECT COUNT(*) FROM vector WHERE model_id = ?", [.text(model)]))?.first?.first?.int ?? 0)
    }
}
