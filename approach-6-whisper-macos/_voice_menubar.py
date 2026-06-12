"""macOS 選單列圖示（rumps）"""
from __future__ import annotations

import logging
import os

from _voice_instance import remove_pid_file

logger = logging.getLogger(__name__)

_status_label = {"text": "⏸ 待機"}


def build_menubar_app(mode_manager):
    """建立 rumps 選單列 App（不啟動）。
    回傳 app 物件供 main() 在主執行緒呼叫 .run()。
    macOS 26 要求 NSApplication 必須在主執行緒初始化。
    """
    try:
        import rumps

        class VoiceTypingApp(rumps.App):
            def __init__(self):
                super().__init__("🎤", quit_button=None)
                self._mm = mode_manager
                self._rebuild_menu()

            def _rebuild_menu(self):
                items = []
                for mode in self._mm.all:
                    def _make_cb(mid):
                        def cb(_):
                            self._mm.set_by_id(mid)
                            logger.info("🔀 模式 → %s", self._mm.current.display)
                        return cb
                    items.append(rumps.MenuItem(mode.display, callback=_make_cb(mode.id)))
                items.append(None)
                items.append(rumps.MenuItem(
                    "❌ 結束程式",
                    callback=lambda _: (remove_pid_file(), os._exit(0)),
                ))
                self.menu = items

            @rumps.timer(0.4)
            def update_status(self, _):
                self.title = _status_label["text"]

        return VoiceTypingApp()

    except ImportError:
        logger.info("ℹ️  rumps 未安裝，跳過選單列圖示（功能不受影響）")
        return None
    except Exception as e:
        logger.info("ℹ️  rumps 初始化失敗（%s），跳過選單列圖示", e)
        return None


def set_menubar_state(state: str):
    states = {
        "idle":       "⏸ 待機",
        "recording":  "🔴 錄音中",
        "processing": "🔄 辨識中",
        "error":      "⚠️ 錯誤",
    }
    _status_label["text"] = states.get(state, "⏸ 待機")
