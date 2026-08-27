import Foundation
import SQLite3

struct SessionMetadata {
    let customName: String?
    let isPinned: Bool
}

final class SessionMetadataStore {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let manager = FileManager.default
        let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steady", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("sessions.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            database = nil
            return
        }

        execute("""
        CREATE TABLE IF NOT EXISTS session_metadata (
            session_key TEXT PRIMARY KEY NOT NULL,
            custom_name TEXT,
            pinned INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        );
        """)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func metadata(for key: String) -> SessionMetadata {
        guard let database else { return SessionMetadata(customName: nil, isPinned: false) }
        let query = "SELECT custom_name, pinned FROM session_metadata WHERE session_key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return SessionMetadata(customName: nil, isPinned: false)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return SessionMetadata(customName: nil, isPinned: false)
        }

        let customName = sqlite3_column_text(statement, 0).map { String(cString: $0) }
        return SessionMetadata(customName: customName, isPinned: sqlite3_column_int(statement, 1) == 1)
    }

    func setName(_ name: String?, for key: String) {
        let current = metadata(for: key)
        save(SessionMetadata(customName: name, isPinned: current.isPinned), for: key)
    }

    func setPinned(_ pinned: Bool, for key: String) {
        let current = metadata(for: key)
        save(SessionMetadata(customName: current.customName, isPinned: pinned), for: key)
    }

    private func save(_ metadata: SessionMetadata, for key: String) {
        guard let database else { return }
        let query = """
        INSERT INTO session_metadata (session_key, custom_name, pinned, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(session_key) DO UPDATE SET
            custom_name = excluded.custom_name,
            pinned = excluded.pinned,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, transient)
        if let name = metadata.customName, !name.isEmpty {
            sqlite3_bind_text(statement, 2, name, -1, transient)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        sqlite3_bind_int(statement, 3, metadata.isPinned ? 1 : 0)
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
        _ = sqlite3_step(statement)
    }

    private func execute(_ query: String) {
        guard let database else { return }
        sqlite3_exec(database, query, nil, nil, nil)
    }
}
