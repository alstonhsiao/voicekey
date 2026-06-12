"""SQLite session logger：每次辨識完成記一筆，方便 bug 追蹤與改善分析。"""
from __future__ import annotations

import logging
import os
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class SessionLogger:
    DB_PATH = Path.home() / ".whisper_voice_log.db"

    _CREATE_SQL = """
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

    def __init__(self):
        self._conn = sqlite3.connect(str(self.DB_PATH), check_same_thread=False)
        os.chmod(self.DB_PATH, 0o600)
        self._lock = threading.Lock()
        self._conn.execute(self._CREATE_SQL)
        self._conn.commit()
        self._migrate()
        logger.info("📊 Session log: %s", self.DB_PATH)

    def _migrate(self):
        new_cols = [("llm_finish_reason", "TEXT")]
        for col, col_type in new_cols:
            try:
                self._conn.execute(f"ALTER TABLE sessions ADD COLUMN {col} {col_type}")
                self._conn.commit()
            except sqlite3.OperationalError:
                pass  # 欄位已存在

    def log(self, **kwargs):
        cols = list(kwargs.keys())
        vals = list(kwargs.values())
        sql = (
            f"INSERT INTO sessions ({', '.join(cols)}) "
            f"VALUES ({', '.join(['?'] * len(cols))})"
        )
        try:
            with self._lock:
                self._conn.execute(sql, vals)
                self._conn.commit()
        except Exception as e:
            logger.warning("⚠️  session log 寫入失敗（%s）", e)
