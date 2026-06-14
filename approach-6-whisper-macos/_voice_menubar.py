"""macOS 選單列圖示（rumps）"""
from __future__ import annotations

import logging
import os
import subprocess

from _voice_instance import remove_pid_file

logger = logging.getLogger(__name__)

_status_label = {"text": "⏸ 待機"}


def _open_vocab(path: str, args: list[str], label: str):
    """以 subprocess 開啟詞彙檔。任何失敗只 log，不崩潰。"""
    try:
        subprocess.run(args, check=True)
        logger.info("📂 詞彙檔：%s（%s）", label, path)
    except Exception as e:
        logger.warning("⚠️  %s失敗（%s）— 路徑：%s", label, e, path)


def build_menubar_app(mode_manager, vocab_path=None):
    """建立 rumps 選單列 App（不啟動）。
    回傳 app 物件供 main() 在主執行緒呼叫 .run()。
    macOS 26 要求 NSApplication 必須在主執行緒初始化。
    vocab_path：user_vocab.json 絕對路徑，用於「管理詞彙」子選單。
    """
    vocab_path_str = str(vocab_path) if vocab_path else ""

    try:
        import rumps

        class VoiceTypingApp(rumps.App):
            def __init__(self):
                super().__init__("🎤", quit_button=None)
                self._mm = mode_manager
                self._rebuild_menu()

            def _build_vocab_submenu(self):
                """管理詞彙子選單：路徑顯示（灰字）+ 三個開啟動作。"""
                parent = rumps.MenuItem("🗂 管理詞彙")
                # disabled 標題（無 callback → 灰色不可點）
                parent.add(rumps.MenuItem("📄 user_vocab.json"))
                parent.add(rumps.MenuItem(vocab_path_str or "(未設定路徑)"))
                parent.add(rumps.separator)
                parent.add(rumps.MenuItem(
                    "用 VSCode 開啟",
                    callback=lambda _: _open_vocab(
                        vocab_path_str,
                        ["open", "-a", "Visual Studio Code", vocab_path_str],
                        "用 VSCode 開啟",
                    ),
                ))
                parent.add(rumps.MenuItem(
                    "用預設 App 開啟",
                    callback=lambda _: _open_vocab(
                        vocab_path_str, ["open", vocab_path_str], "用預設 App 開啟",
                    ),
                ))
                parent.add(rumps.MenuItem(
                    "在 Finder 中顯示",
                    callback=lambda _: _open_vocab(
                        vocab_path_str, ["open", "-R", vocab_path_str], "在 Finder 中顯示",
                    ),
                ))
                return parent

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
                if vocab_path_str:
                    try:
                        items.append(self._build_vocab_submenu())
                        items.append(None)
                    except Exception as e:
                        logger.warning("⚠️  管理詞彙子選單建立失敗，略過（%s）", e)
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
