"""防重複啟動（fcntl lockfile + PID 檔）"""
from __future__ import annotations

import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)

_lock_file_handle = None
_APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "WhisperVoice"
_PID_FILE = _APP_SUPPORT_DIR / "WhisperVoice.pid"


def write_pid_file() -> None:
    _APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    _PID_FILE.write_text(str(os.getpid()))


def remove_pid_file() -> None:
    _PID_FILE.unlink(missing_ok=True)


def ensure_single_instance(app_name: str = "WhisperVoiceTypingMac") -> bool:
    """使用 lockfile + fcntl.flock 防止重複啟動"""
    global _lock_file_handle
    _APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    lock_path = _APP_SUPPORT_DIR / f"{app_name}.lock"
    try:
        import fcntl
        _lock_file_handle = open(lock_path, "w")
        fcntl.flock(_lock_file_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        _lock_file_handle.write(str(os.getpid()))
        _lock_file_handle.flush()
        return True
    except (IOError, OSError):
        logger.warning("⚠️  程式已經在執行中（lock: %s）", lock_path)
        return False
    except ImportError:
        return True
