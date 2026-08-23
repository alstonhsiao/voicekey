import Foundation
import SQLite3

/// One row per transcription. Mirrors approach-6 `_voice_session.py` sessions table.
struct SessionRecord {
    var timestamp: String
    var appVersion: String? = nil
    var appBuild: String? = nil
    var modeId: String? = nil
    var modeName: String? = nil
    var provider: String? = nil
    var audioSec: Double? = nil
    var audioBytes: Int? = nil
    var stopMs: Int? = nil
    var rawStt: String? = nil
    var regexOut: String? = nil
    var regexMs: Int? = nil
    var llmOut: String? = nil
    var vocabOut: String? = nil
    var vocabMs: Int? = nil
    var finalText: String? = nil
    var sttMs: Int? = nil
    var llmMs: Int? = nil
    var pasteMethod: String? = nil
    var pasteOk: Int? = nil
    var pasteMs: Int? = nil
    var pipelineMs: Int? = nil
    var llmFinishReason: String? = nil
    var errorType: String? = nil
    var errorDetail: String? = nil
}

/// SQLite session logger via libsqlite3 (zero external dependencies).
/// DB at ~/.voicekey_log.db, chmod 600. Serialized writes.
/// First launch copies the pre-rename ~/.whisper_voice_log.db to keep history.
final class SessionLogger {
    static let dbPath: URL = {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let new = home.appendingPathComponent(".voicekey_log.db")
        let legacy = home.appendingPathComponent(".whisper_voice_log.db")
        if !fm.fileExists(atPath: new.path), fm.fileExists(atPath: legacy.path) {
            try? fm.copyItem(at: legacy, to: new)
        }
        return new
    }()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.alston.VoiceKey.sessionlog")
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)  // SQLITE_TRANSIENT

    private static let createSQL = """
    CREATE TABLE IF NOT EXISTS sessions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp    TEXT    NOT NULL,
        app_version  TEXT,
        app_build    TEXT,
        mode_id      TEXT,
        mode_name    TEXT,
        provider     TEXT,
        audio_sec    REAL,
        audio_bytes  INTEGER,
        stop_ms      INTEGER,
        raw_stt      TEXT,
        regex_out    TEXT,
        regex_ms     INTEGER,
        llm_out      TEXT,
        vocab_out    TEXT,
        vocab_ms     INTEGER,
        final_text   TEXT,
        stt_ms       INTEGER,
        llm_ms       INTEGER,
        paste_method TEXT,
        paste_ok     INTEGER,
        paste_ms     INTEGER,
        pipeline_ms  INTEGER,
        llm_finish_reason TEXT,
        error_type   TEXT,
        error_detail TEXT
    )
    """

    init(databaseURL: URL = SessionLogger.dbPath) {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            AppLog.warn("⚠️ session log 開啟失敗：\(databaseURL.path)")
            db = nil
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: databaseURL.path)
        exec(Self.createSQL)
        migrate()
        AppLog.info("📊 Session log: \(databaseURL.path)")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func migrate() {
        let additions = [
            ("llm_finish_reason", "TEXT"),
            ("vocab_out", "TEXT"),
            ("app_version", "TEXT"),
            ("app_build", "TEXT"),
            ("audio_bytes", "INTEGER"),
            ("stop_ms", "INTEGER"),
            ("regex_ms", "INTEGER"),
            ("vocab_ms", "INTEGER"),
            ("paste_ms", "INTEGER"),
            ("pipeline_ms", "INTEGER"),
        ]
        let existing = sessionColumns()
        for (name, type) in additions where !existing.contains(name) {
            exec("ALTER TABLE sessions ADD COLUMN \(name) \(type)")
        }
    }

    private func sessionColumns() -> Set<String> {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(sessions)", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var columns = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW, let rawName = sqlite3_column_text(stmt, 1) {
            columns.insert(String(cString: rawName))
        }
        return columns
    }

    func log(_ r: SessionRecord) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO sessions
            (timestamp, app_version, app_build, mode_id, mode_name, provider, audio_sec,
             audio_bytes, stop_ms, raw_stt, regex_out, regex_ms, llm_out, vocab_out,
             vocab_ms, final_text, stt_ms, llm_ms, paste_method, paste_ok, paste_ms,
             pipeline_ms, llm_finish_reason, error_type, error_detail)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                AppLog.warn("⚠️ session log prepare 失敗")
                return
            }
            defer { sqlite3_finalize(stmt) }

            let T = self.transient
            func text(_ i: Int32, _ s: String?) {
                if let s { sqlite3_bind_text(stmt, i, s, -1, T) } else { sqlite3_bind_null(stmt, i) }
            }
            func int(_ i: Int32, _ v: Int?) {
                if let v { sqlite3_bind_int(stmt, i, Int32(v)) } else { sqlite3_bind_null(stmt, i) }
            }
            func dbl(_ i: Int32, _ v: Double?) {
                if let v { sqlite3_bind_double(stmt, i, v) } else { sqlite3_bind_null(stmt, i) }
            }

            text(1, r.timestamp)
            text(2, r.appVersion)
            text(3, r.appBuild)
            text(4, r.modeId)
            text(5, r.modeName)
            text(6, r.provider)
            dbl(7, r.audioSec)
            int(8, r.audioBytes)
            int(9, r.stopMs)
            text(10, r.rawStt)
            text(11, r.regexOut)
            int(12, r.regexMs)
            text(13, r.llmOut)
            text(14, r.vocabOut)
            int(15, r.vocabMs)
            text(16, r.finalText)
            int(17, r.sttMs)
            int(18, r.llmMs)
            text(19, r.pasteMethod)
            int(20, r.pasteOk)
            int(21, r.pasteMs)
            int(22, r.pipelineMs)
            text(23, r.llmFinishReason)
            text(24, r.errorType)
            text(25, r.errorDetail)

            if sqlite3_step(stmt) != SQLITE_DONE {
                AppLog.warn("⚠️ session log 寫入失敗")
            }
        }
    }

    /// Wait for queued writes. Used by tests and orderly benchmark collection.
    func flush() {
        queue.sync {}
    }
}
