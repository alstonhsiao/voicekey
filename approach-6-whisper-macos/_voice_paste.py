"""貼上模組：beep、前景 App 偵測、GCD 主執行緒 dispatch、paste_text"""
from __future__ import annotations

import ctypes
import logging
import os
import subprocess
import threading
import time

import pyperclip

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Beep
# ---------------------------------------------------------------------------

def beep():
    try:
        os.system("afplay /System/Library/Sounds/Tink.aiff &")
    except Exception:
        print("\a", end="", flush=True)


# ---------------------------------------------------------------------------
# 前景 App 偵測
# ---------------------------------------------------------------------------

def get_frontmost_app() -> str:
    """回傳目前前景 App 的 process 名稱。"""
    try:
        r = subprocess.run(
            ["osascript", "-e",
             "tell application \"System Events\" to get name of first process whose frontmost is true"],
            capture_output=True, text=True, timeout=2,
        )
        return r.stdout.strip()
    except Exception:
        return ""


# ---------------------------------------------------------------------------
# GCD 主執行緒 dispatch（修正 macOS 26+ TSM 執行緒斷言）
# macOS 26 在 HIToolbox 新增 dispatch_assert_queue 斷言：
# TSMGetInputSourceProperty / islGetInputSourceListWithAdditions 只能在主執行緒呼叫。
# pynput.keyboard.Controller 內部用 ctypes 呼叫上述 API，
# 若從背景執行緒觸發會直接 SIGTRAP 崩潰，需用 GCD 排程到主執行緒執行。
# ---------------------------------------------------------------------------

_gcd_lib = None
_gcd_main_queue = 0
_gcd_async_f = None
_gcd_work_fn_type = None
_gcd_main_q_anchor = None  # 防止 GC


def _gcd_init() -> bool:
    global _gcd_lib, _gcd_main_queue, _gcd_async_f, _gcd_work_fn_type, _gcd_main_q_anchor
    if _gcd_lib is not None:
        return bool(_gcd_main_queue)
    try:
        lib = ctypes.CDLL('/usr/lib/system/libdispatch.dylib')
        # dispatch_get_main_queue() 在 macOS 26 是 macro → &_dispatch_main_q
        try:
            get_mq = lib.dispatch_get_main_queue
            get_mq.restype = ctypes.c_void_p
            get_mq.argtypes = []
            main_queue = get_mq()
        except AttributeError:
            anchor = ctypes.c_uint64.in_dll(lib, '_dispatch_main_q')
            _gcd_main_q_anchor = anchor
            main_queue = ctypes.addressof(anchor)
        af = lib.dispatch_async_f
        af.restype = None
        af.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        _gcd_lib = lib
        _gcd_main_queue = main_queue
        _gcd_async_f = af
        _gcd_work_fn_type = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
        return True
    except Exception:
        _gcd_lib = False
        return False


def _run_on_main_thread(fn, timeout: float = 5.0) -> bool:
    """從背景執行緒將 fn 排程到 GCD 主執行緒執行，等待完成後返回。"""
    if not _gcd_init():
        return False
    done = threading.Event()

    def wrapper(_ctx):
        try:
            fn()
        finally:
            done.set()

    cb = _gcd_work_fn_type(wrapper)
    _gcd_async_f(_gcd_main_queue, None, cb)
    done.wait(timeout=timeout)
    return done.is_set()


# ---------------------------------------------------------------------------
# 貼上
# ---------------------------------------------------------------------------

def paste_text(text: str, target_app: str = "") -> tuple[str, bool]:
    pyperclip.copy(text)
    time.sleep(0.1)

    # 方案 A（主）：osascript activate 目標 App → keystroke Cmd+V
    if target_app:
        logger.debug("🪵 paste target app: %s", target_app)
        target_app_escaped = target_app.replace("\\", "\\\\").replace('"', '\\"')
        script = (
            f'tell application "{target_app_escaped}" to activate\n'
            f'delay 0.12\n'
            f'tell application "System Events"\n'
            f'    keystroke "v" using command down\n'
            f'end tell'
        )
        result = subprocess.run(["osascript", "-e", script], capture_output=True)
        if result.returncode == 0:
            logger.debug("🪵 paste method: osascript")
            return "osascript", True
        stderr = result.stderr.decode().strip()
        logger.warning("⚠️  osascript 自動貼上失敗（%s）", stderr)
        logger.warning("   請確認：系統設定 → 隱私權與安全性 → 輔助使用")
        logger.warning("   啟動用的 App 需授權：Terminal / iTerm / PyCharm / VS Code")

    # 方案 B（fallback）：pynput 直送 Cmd+V（GCD 主執行緒）
    def _pynput_cmd_v():
        from pynput.keyboard import Controller, Key
        kb = Controller()
        kb.press(Key.cmd)
        kb.press("v")
        kb.release("v")
        kb.release(Key.cmd)

    if _run_on_main_thread(_pynput_cmd_v):
        logger.debug("🪵 paste method: pynput (main thread)")
        return "pynput", True

    logger.warning("⚠️  pynput 貼上失敗，文字已存入剪貼簿，請手動 Cmd+V")
    return "clipboard_only", False
