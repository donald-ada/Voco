import Foundation
import SQLite3
import VocoAppCore

final class MacVoiceInputSessionStore: VoiceInputSessionStoring {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(
        databaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let resolvedDatabaseURL = try databaseURL ?? MacVoiceInputSessionStore.defaultDatabaseURL(fileManager: fileManager)
        self.databaseURL = resolvedDatabaseURL

        try fileManager.createDirectory(
            at: resolvedDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try openDatabase()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    static func makeDefault() -> any VoiceInputSessionStoring {
        do {
            return try MacVoiceInputSessionStore()
        } catch {
            NSLog("Voco: 无法打开 SQLite 会话记录，将临时使用内存记录：\(error.localizedDescription)")
            return InMemoryVoiceInputSessionStore()
        }
    }

    static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw VoiceInputSessionStoreError.loadFailed(message: "无法定位 Application Support 目录。")
        }

        return applicationSupportURL
            .appendingPathComponent("Voco", isDirectory: true)
            .appendingPathComponent("voice-input-sessions.sqlite")
    }

    func loadRecentSessions(limit: Int) throws -> [VoiceInputSessionSnapshot] {
        let normalizedLimit = max(0, limit)
        guard normalizedLimit > 0 else {
            return []
        }

        let statement = try prepare(
            """
            SELECT
                id,
                transcript_text,
                raw_transcript_text,
                post_processing_diagnostics_json,
                word_count,
                duration_seconds,
                created_at,
                target_app_name,
                provider_name
            FROM voice_input_sessions
            ORDER BY created_at DESC, rowid DESC
            LIMIT ?;
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bindInt(normalizedLimit, to: 1, in: statement)

        var sessions: [VoiceInputSessionSnapshot] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                return sessions
            }

            guard stepResult == SQLITE_ROW else {
                throw VoiceInputSessionStoreError.loadFailed(message: databaseErrorMessage)
            }

            sessions.append(try readSession(from: statement))
        }
    }

    func save(_ session: VoiceInputSessionSnapshot) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try insertOrReplace(session)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func trimRecentSessions(limit: Int?) throws {
        guard let limit else {
            return
        }

        try trimOldSessions(limit: max(0, limit))
    }

    private func openDatabase() throws {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &connection, flags, nil)

        guard result == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite 连接不可用。"
            sqlite3_close(connection)
            throw VoiceInputSessionStoreError.loadFailed(message: message)
        }

        database = connection
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS voice_input_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                transcript_text TEXT NOT NULL,
                word_count INTEGER NOT NULL,
                duration_seconds REAL NOT NULL,
                created_at REAL NOT NULL,
                target_app_name TEXT,
                provider_name TEXT NOT NULL
            );
            """
        )
        try addColumnIfMissing(name: "raw_transcript_text", definition: "TEXT")
        try addColumnIfMissing(name: "post_processing_diagnostics_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try execute(
            """
            UPDATE voice_input_sessions
            SET raw_transcript_text = transcript_text
            WHERE raw_transcript_text IS NULL;
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_created_at
            ON voice_input_sessions(created_at DESC);
            """
        )
    }

    private func insertOrReplace(_ session: VoiceInputSessionSnapshot) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO voice_input_sessions (
                id,
                transcript_text,
                raw_transcript_text,
                post_processing_diagnostics_json,
                word_count,
                duration_seconds,
                created_at,
                target_app_name,
                provider_name
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        let postProcessingDiagnosticsJSON = try diagnosticsJSON(session.postProcessingDiagnostics)
        try bindText(session.id.uuidString, to: 1, in: statement)
        try bindText(session.transcriptText, to: 2, in: statement)
        try bindText(session.rawTranscriptText, to: 3, in: statement)
        try bindText(postProcessingDiagnosticsJSON, to: 4, in: statement)
        try bindInt(session.wordCount, to: 5, in: statement)
        try bindDouble(session.durationSeconds, to: 6, in: statement)
        try bindDouble(session.createdAt.timeIntervalSince1970, to: 7, in: statement)
        try bindNullableText(session.targetAppName, to: 8, in: statement)
        try bindText(session.providerName, to: 9, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
        }
    }

    private func trimOldSessions(limit: Int) throws {
        let statement = try prepare(
            """
            DELETE FROM voice_input_sessions
            WHERE id NOT IN (
                SELECT id
                FROM voice_input_sessions
                ORDER BY created_at DESC, rowid DESC
                LIMIT ?
            );
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bindInt(limit, to: 1, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
        }
    }

    private func addColumnIfMissing(name: String, definition: String) throws {
        let columns = try tableColumns()
        guard !columns.contains(name) else {
            return
        }

        try execute("ALTER TABLE voice_input_sessions ADD COLUMN \(name) \(definition);")
    }

    private func tableColumns() throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(voice_input_sessions);")
        defer {
            sqlite3_finalize(statement)
        }

        var columns = Set<String>()
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                return columns
            }

            guard stepResult == SQLITE_ROW else {
                throw VoiceInputSessionStoreError.loadFailed(message: databaseErrorMessage)
            }

            if let name = columnText(statement, 1) {
                columns.insert(name)
            }
        }
    }

    private func diagnosticsJSON(_ diagnostics: [TranscriptPostProcessingDiagnostic]) throws -> String {
        do {
            let data = try JSONEncoder().encode(diagnostics)
            guard let json = String(data: data, encoding: .utf8) else {
                throw VoiceInputSessionStoreError.saveFailed(message: "无法将 post-processing diagnostics 编码为 UTF-8。")
            }
            return json
        } catch let error as VoiceInputSessionStoreError {
            throw error
        } catch {
            throw VoiceInputSessionStoreError.saveFailed(
                message: "无法编码 post-processing diagnostics：\(error.localizedDescription)"
            )
        }
    }

    private func decodeDiagnostics(_ json: String?) throws -> [TranscriptPostProcessingDiagnostic] {
        guard let json,
              !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return []
        }

        do {
            return try JSONDecoder().decode([TranscriptPostProcessingDiagnostic].self, from: Data(json.utf8))
        } catch {
            throw VoiceInputSessionStoreError.loadFailed(
                message: "无法解码 post-processing diagnostics：\(error.localizedDescription)"
            )
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw VoiceInputSessionStoreError.loadFailed(message: databaseErrorMessage)
        }

        return statement
    }

    private func readSession(from statement: OpaquePointer?) throws -> VoiceInputSessionSnapshot {
        guard
            let idText = columnText(statement, 0),
            let id = UUID(uuidString: idText),
            let transcriptText = columnText(statement, 1),
            let providerName = columnText(statement, 8)
        else {
            throw VoiceInputSessionStoreError.loadFailed(message: "数据库中存在格式无效的会话记录。")
        }

        let rawTranscriptText = columnText(statement, 2) ?? transcriptText
        let postProcessingDiagnostics = try decodeDiagnostics(columnText(statement, 3))
        let targetAppName = columnText(statement, 7)
        return VoiceInputSessionSnapshot(
            id: id,
            transcriptText: transcriptText,
            rawTranscriptText: rawTranscriptText,
            postProcessingDiagnostics: postProcessingDiagnostics,
            wordCount: Int(sqlite3_column_int64(statement, 4)),
            durationSeconds: sqlite3_column_double(statement, 5),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            targetAppName: targetAppName,
            providerName: providerName
        )
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer?) throws {
        let result = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransientDestructor)
        }
        guard result == SQLITE_OK else {
            throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
        }
    }

    private func bindNullableText(_ value: String?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
            }
            return
        }

        try bindText(value, to: index, in: statement)
    }

    private func bindInt(_ value: Int, to index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
        }
    }

    private func bindDouble(_ value: Double, to index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw VoiceInputSessionStoreError.saveFailed(message: databaseErrorMessage)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else {
            return nil
        }

        return String(cString: text)
    }

    private var databaseErrorMessage: String {
        guard let database else {
            return "SQLite 连接不可用。"
        }

        return String(cString: sqlite3_errmsg(database))
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
