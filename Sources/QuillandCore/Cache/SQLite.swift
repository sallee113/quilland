import Foundation
import SQLite3

/// A thin wrapper over the system SQLite (no dependency to add).
final class SQLiteDatabase {
    struct Failure: Error, CustomStringConvertible {
        var message: String
        var description: String { message }
    }

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw Failure(message: message)
        }
    }

    deinit { sqlite3_close(handle) }

    var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw Failure(message: "\(message) in: \(sql.prefix(80))")
        }
    }

    enum Value {
        case int(Int)
        case text(String)
        case null
    }

    final class Statement {
        fileprivate var raw: OpaquePointer?
        fileprivate let db: SQLiteDatabase
        init(_ db: SQLiteDatabase, _ sql: String) throws {
            self.db = db
            if sqlite3_prepare_v2(db.handle, sql, -1, &raw, nil) != SQLITE_OK { throw Failure(message: "\(db.lastError) in: \(sql.prefix(80))") }
        }
        deinit { sqlite3_finalize(raw) }

        func bind(_ values: [Value]) {
            sqlite3_reset(raw)
            sqlite3_clear_bindings(raw)
            for (i, value) in values.enumerated() {
                let index = Int32(i + 1)
                switch value {
                case .int(let n): sqlite3_bind_int64(raw, index, Int64(n))
                case .text(let s): sqlite3_bind_text(raw, index, s, -1, SQLiteDatabase.transient)
                case .null: sqlite3_bind_null(raw, index)
                }
            }
        }

        /// Runs a statement that returns no rows.
        func run(_ values: [Value] = []) throws {
            bind(values)
            let code = sqlite3_step(raw)
            if code != SQLITE_DONE && code != SQLITE_ROW { throw Failure(message: db.lastError) }
        }

        /// Calls `row` for each result row.
        func rows(_ values: [Value] = [], _ row: (Row) throws -> Void) throws {
            bind(values)
            while true {
                let code = sqlite3_step(raw)
                if code == SQLITE_ROW { try row(Row(raw!)) }
                else if code == SQLITE_DONE { return }
                else { throw Failure(message: db.lastError) }
            }
        }
    }

    struct Row {
        let raw: OpaquePointer
        init(_ raw: OpaquePointer) { self.raw = raw }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(raw, i)) }
        func text(_ i: Int32) -> String { sqlite3_column_text(raw, i).map { String(cString: $0) } ?? "" }
    }

    func prepare(_ sql: String) throws -> Statement { try Statement(self, sql) }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error }
    }

    /// The first column of the first row.
    func scalar(_ sql: String, _ values: [Value] = []) throws -> Int {
        var result = 0
        try prepare(sql).rows(values) { result = $0.int(0) }
        return result
    }
}
