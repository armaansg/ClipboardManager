import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    static func optionalText(_ value: String?) -> SQLValue { value.map { .text($0) } ?? .null }
    static func optionalInt(_ value: Int?) -> SQLValue { value.map { .int(Int64($0)) } ?? .null }
    static func optionalDate(_ value: Date?) -> SQLValue { value.map { .double($0.timeIntervalSince1970) } ?? .null }
    static func bool(_ value: Bool) -> SQLValue { .int(value ? 1 : 0) }
    static func date(_ value: Date) -> SQLValue { .double(value.timeIntervalSince1970) }
}

struct SQLiteError: Error, CustomStringConvertible {
    let message: String
    let code: Int32
    var description: String { "SQLite error \(code): \(message)" }
}

struct SQLRow {
    let statement: OpaquePointer

    func int(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
    func bool(_ index: Int32) -> Bool { sqlite3_column_int64(statement, index) != 0 }
    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(statement, index) == SQLITE_NULL }
    func text(_ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }
    func optionalInt(_ index: Int32) -> Int? { isNull(index) ? nil : Int(int(index)) }
    func optionalDate(_ index: Int32) -> Date? { isNull(index) ? nil : Date(timeIntervalSince1970: double(index)) }
    func date(_ index: Int32) -> Date { Date(timeIntervalSince1970: double(index)) }
}

/// Minimal wrapper over the system SQLite library. Not thread-safe by itself; HistoryStore serializes access.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(db)
            throw SQLiteError(message: message, code: rc)
        }
        handle = db
        sqlite3_busy_timeout(db, 2_000)
    }

    deinit {
        sqlite3_close(handle)
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }

    func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if rc != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorPointer)
            throw SQLiteError(message: message, code: rc)
        }
    }

    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError(message: lastErrorMessage, code: rc)
        }
    }

    func query<T>(_ sql: String, _ params: [SQLValue] = [], _ transform: (SQLRow) throws -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                results.append(try transform(SQLRow(statement: statement)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError(message: lastErrorMessage, code: rc)
            }
        }
        return results
    }

    func scalarInt(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        try query(sql, params) { $0.int(0) }.first ?? 0
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            throw SQLiteError(message: lastErrorMessage, code: rc)
        }
        for (offset, value) in params.enumerated() {
            let index = Int32(offset + 1)
            let bindResult: Int32
            switch value {
            case .null:
                bindResult = sqlite3_bind_null(statement, index)
            case .int(let v):
                bindResult = sqlite3_bind_int64(statement, index, v)
            case .double(let v):
                bindResult = sqlite3_bind_double(statement, index, v)
            case .text(let v):
                bindResult = sqlite3_bind_text(statement, index, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                if v.isEmpty {
                    bindResult = sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    bindResult = v.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
                    }
                }
            }
            guard bindResult == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw SQLiteError(message: lastErrorMessage, code: bindResult)
            }
        }
        return statement
    }
}
