import Foundation
import SQLite3

nonisolated enum AreaError: Error { case database(String), invalidGeometry, invalidBundle }

/// Small scoped wrapper. Each handle belongs to one indexing task.
nonisolated final class AreaDatabase {
    private var handle: OpaquePointer?
    init(_ url: URL, writable: Bool = false) throws {
        let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            handle = nil
            throw AreaError.database(message)
        }
        sqlite3_busy_timeout(handle, 5000)
    }
    deinit { sqlite3_close(handle) }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error }
    }
    private var error: AreaError { .database(String(cString: sqlite3_errmsg(handle))) }
    func statement(_ sql: String) throws -> AreaStatement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error }
        return AreaStatement(stmt, owner: self)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}

nonisolated final class AreaStatement {
    private let pointer: OpaquePointer
    private let owner: AreaDatabase
    init(_ pointer: OpaquePointer, owner: AreaDatabase) {
        self.pointer = pointer
        self.owner = owner
    }
    deinit { sqlite3_finalize(pointer) }
    func reset() { sqlite3_reset(pointer); sqlite3_clear_bindings(pointer) }
    func bind(_ value: Double, _ index: Int32) { sqlite3_bind_double(pointer, index, value) }
    func bind(_ value: Int, _ index: Int32) { sqlite3_bind_int64(pointer, index, Int64(value)) }
    func bind(_ value: String, _ index: Int32) {
        sqlite3_bind_text(pointer, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    func step() throws -> Bool {
        switch sqlite3_step(pointer) {
        case SQLITE_ROW: true
        case SQLITE_DONE: false
        default: throw AreaError.database(String(cString: sqlite3_errmsg(sqlite3_db_handle(pointer))))
        }
    }
    func text(_ i: Int32) -> String { sqlite3_column_text(pointer, i).map { String(cString: $0) } ?? "" }
    func integer(_ i: Int32) -> Int { Int(sqlite3_column_int64(pointer, i)) }
    func blob(_ i: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(pointer, i) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(pointer, i)))
    }
}
