import SQLite3
import XCTest
@testable import VoiceKey

final class SessionLoggerTests: XCTestCase {
    func testPerformanceTelemetrySchemaAndWrite() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceKeySession-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let logger = SessionLogger(databaseURL: url)
        logger.log(SessionRecord(
            timestamp: "2026-08-23T00:00:00Z",
            appVersion: "0.1.0", appBuild: "53",
            modeId: "direct", provider: "grok", audioSec: 4.2,
            audioBytes: 134_444, stopMs: 21,
            regexMs: 0, vocabMs: 3, sttMs: 700, llmMs: 400,
            pasteMethod: "cgevent", pasteOk: 1, pasteMs: 2, pipelineMs: 1_126))
        logger.flush()

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { if let db { sqlite3_close(db) } }

        let sql = """
        SELECT app_version, app_build, audio_bytes, stop_ms, regex_ms, vocab_ms,
               paste_ms, pipeline_ms FROM sessions LIMIT 1
        """
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "0.1.0")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 1)), "53")
        XCTAssertEqual(sqlite3_column_int(stmt, 2), 134_444)
        XCTAssertEqual(sqlite3_column_int(stmt, 3), 21)
        XCTAssertEqual(sqlite3_column_int(stmt, 4), 0)
        XCTAssertEqual(sqlite3_column_int(stmt, 5), 3)
        XCTAssertEqual(sqlite3_column_int(stmt, 6), 2)
        XCTAssertEqual(sqlite3_column_int(stmt, 7), 1_126)
    }

    func testLegacySchemaAddsPerformanceColumns() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceKeyLegacySession-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE sessions (id INTEGER PRIMARY KEY, timestamp TEXT NOT NULL)",
                                    nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let logger = SessionLogger(databaseURL: url)
        logger.flush()

        db = nil
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { if let db { sqlite3_close(db) } }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT pipeline_ms FROM sessions", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
    }
}
