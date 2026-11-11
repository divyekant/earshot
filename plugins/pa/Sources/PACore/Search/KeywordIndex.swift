import Foundation

/// A keyword index over short texts in one SQLite table (FTS5 with the porter stem rule).
/// A search gives the rows with any of the words, best first (bm25).
public final class KeywordIndex {
    let db: SQLite
    let table: String
    public private(set) var fts5 = true

    public init(db: SQLite, table: String) throws {
        self.db = db
        self.table = table
        do {
            try db.exec("CREATE VIRTUAL TABLE IF NOT EXISTS \(table) USING fts5(body, tokenize='porter unicode61 remove_diacritics 2')")
        } catch {
            // Only an old SQLite has no FTS5. Then the search is a slow scan with LIKE.
            fts5 = false
            try db.exec("CREATE TABLE IF NOT EXISTS \(table) (rowid INTEGER PRIMARY KEY, body TEXT)")
        }
    }

    public func add(_ rowid: Int64, _ text: String) throws {
        try db.run("DELETE FROM \(table) WHERE rowid = ?", [.int(rowid)])
        try db.run("INSERT INTO \(table)(rowid, body) VALUES (?, ?)", [.int(rowid), .text(text)])
    }

    public func remove(_ rowid: Int64) throws {
        try db.run("DELETE FROM \(table) WHERE rowid = ?", [.int(rowid)])
    }

    /// The rowids of the rows with one or more of the words of `text`, best first.
    public func search(_ text: String, limit: Int) -> [Int64] {
        let terms = Fusion.unique(Words.terms(text))
        guard !terms.isEmpty else { return [] }
        let rows: [[SQLValue]]
        if fts5 {
            let q = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
            rows = (try? db.query("SELECT rowid FROM \(table) WHERE \(table) MATCH ? ORDER BY bm25(\(table)) LIMIT ?",
                                  [.text(q), .int(Int64(limit))])) ?? []
        } else {
            let cond = terms.map { _ in "lower(body) LIKE ?" }.joined(separator: " OR ")
            rows = (try? db.query("SELECT rowid FROM \(table) WHERE \(cond) LIMIT ?",
                                  terms.map { .text("%\($0)%") } + [.int(Int64(limit))])) ?? []
        }
        return rows.compactMap { $0.first?.int }
    }
}
