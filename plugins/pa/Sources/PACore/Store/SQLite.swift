import CSQLite
import Foundation

/// One value of a SQLite column.
public enum SQLValue: Equatable, Sendable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)

    public var int: Int64? {
        switch self {
        case .int(let v): return v
        case .real(let v): return Int64(v)
        default: return nil
        }
    }
    public var real: Double? {
        switch self {
        case .real(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    public var text: String? { if case .text(let v) = self { return v } else { return nil } }
}

public struct SQLError: Error, CustomStringConvertible {
    public var code: Int32
    public var message: String
    public var description: String { "SQLite \(code): \(message)" }
}

/// A small wrapper over the C interface of the system SQLite. One connection. The caller owns the thread:
/// the PA uses it from one serial queue only.
public final class SQLite {
    private var db: OpaquePointer?
    public let path: String

    public init(path: String) throws {
        self.path = path
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            db = nil
            throw SQLError(code: rc, message: msg)
        }
        sqlite3_busy_timeout(db, 2000)
    }

    deinit { sqlite3_close(db) }

    public func close() {
        sqlite3_close(db)
        db = nil
    }

    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func error(_ rc: Int32) -> SQLError {
        SQLError(code: rc, message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")
    }

    /// Runs one or more statements with no parameters.
    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "error"
            sqlite3_free(err)
            throw SQLError(code: rc, message: msg)
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw error(rc) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLite.transient)
            }
        }
        return stmt
    }

    /// Runs one statement. Gives the count of changed rows.
    @discardableResult
    public func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW { rc = sqlite3_step(stmt) }
        guard rc == SQLITE_DONE else { throw error(rc) }
        return Int(sqlite3_changes(db))
    }

    /// Runs one query. Gives the rows.
    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[SQLValue]] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [[SQLValue]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error(rc) }
            let n = sqlite3_column_count(stmt)
            var row: [SQLValue] = []
            row.reserveCapacity(Int(n))
            for c in 0..<n {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(stmt, c)))
                case SQLITE_NULL: row.append(.null)
                default:
                    if let p = sqlite3_column_text(stmt, c) { row.append(.text(String(cString: p))) } else { row.append(.null) }
                }
            }
            rows.append(row)
        }
        return rows
    }

    public var lastInsertID: Int64 { sqlite3_last_insert_rowid(db) }

    /// Runs the body in one transaction. If the body throws, the transaction rolls back.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let out = try body()
            try exec("COMMIT")
            return out
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// The version of the SQLite library.
    public static var libraryVersion: String { String(cString: sqlite3_libversion()) }
}
