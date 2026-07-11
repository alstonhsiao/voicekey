import Foundation
import SQLite3

/// One row per transcription. Mirrors approach-6 `_voice_session.py` sessions table.
struct SessionRecord {
    var timestamp: String
    var modeId: String?
    var modeName: String?
    var provider: String?
    var audioSec: Double?
    var rawStt: String?
    var regexOut: String?
    var llmOut: String?
    var vocabOut: String?
    var finalText: String?
    var sttMs: Int?
    var llmMs: Int?
    var pasteMethod: String?
    var pasteOk: Int?
    var llmFinishReason: String?
    var errorType: String?
    var errorDetail: String?
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
        mode_id      TEXT,
        mode_name    TEXT,
        provider     TEXT,
        audio_sec    REAL,
        raw_stt      TEXT,
        regex_out    TEXT,
        llm_out      TEXT,
        final_text   TEXT,
        stt_ms       INTEGER,
        llm_ms       INTEGER,
        paste_method TEXT,
        paste_ok     INTEGER,
        error_type   TEXT,
        error_detail TEXT
    )
    """

    init() {
        if sqlite3_open(Self.dbPath.path, &db) != SQLITE_OK {
            AppLog.warn("⚠️ session log 開啟失敗：\(Self.dbPath.path)")
            db = nil
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: Self.dbPath.path)
        exec(Self.createSQL)
        migrate()
        AppLog.info("📊 Session log: \(Self.dbPath.path)")
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
        // Late-added columns (ignore "duplicate column" errors).
        exec("ALTER TABLE sessions ADD COLUMN llm_finish_reason TEXT")
        exec("ALTER TABLE sessions ADD COLUMN vocab_out TEXT")
    }

    func log(_ r: SessionRecord) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = """
            INSERT INTO sessions
            (timestamp, mode_id, mode_name, provider, audio_sec, raw_stt, regex_out,
             llm_out, vocab_out, final_text, stt_ms, llm_ms, paste_method, paste_ok,
             llm_finish_reason, error_type, error_detail)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
            text(2, r.modeId)
            text(3, r.modeName)
            text(4, r.provider)
            dbl(5, r.audioSec)
            text(6, r.rawStt)
            text(7, r.regexOut)
            text(8, r.llmOut)
            text(9, r.vocabOut)
            text(10, r.finalText)
            int(11, r.sttMs)
            int(12, r.llmMs)
            text(13, r.pasteMethod)
            int(14, r.pasteOk)
            text(15, r.llmFinishReason)
            text(16, r.errorType)
            text(17, r.errorDetail)

            if sqlite3_step(stmt) != SQLITE_DONE {
                AppLog.warn("⚠️ session log 寫入失敗")
            }
        }
    }
}
