"""設定載入、Mode / ModeManager、config schema 驗證"""
from __future__ import annotations

import json
import logging
import os
import sys
import threading
from pathlib import Path

logger = logging.getLogger(__name__)


def get_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).parent
    return Path(__file__).parent


# ---------------------------------------------------------------------------
# Mode 系統
# ---------------------------------------------------------------------------

class Mode:
    def __init__(self, raw: dict):
        self.id = raw["id"]
        self.name = raw["name"]
        self.icon = raw.get("icon", "📝")
        self.language = raw.get("language", "zh")
        self.translate_to_english = raw.get("translate_to_english", False)
        self.prompt = raw.get("prompt", "")
        self.regex_rules = raw.get("regex_rules", [])
        self.grok_keyterms = raw.get("grok_keyterms", [])
        self.llm_prompt = raw.get("llm_prompt", "")

        # 向後相容：若無 grok_keyterms，從 prompt 提取
        if not self.grok_keyterms and self.prompt:
            self.grok_keyterms = [
                kw.strip() for kw in self.prompt.split(",") if kw.strip()
            ]

    @property
    def display(self) -> str:
        return f"{self.icon} {self.name}"


class ModeManager:
    """管理可切換的轉錄模式。執行緒安全。"""

    def __init__(self, modes: list[dict], default_id: str):
        self._modes = [Mode(m) for m in modes]
        if not self._modes:
            raise ValueError("config.modes 不可為空")
        self._index = 0
        for i, m in enumerate(self._modes):
            if m.id == default_id:
                self._index = i
                break
        self._lock = threading.Lock()
        self._listeners: list = []

    @property
    def current(self) -> Mode:
        with self._lock:
            return self._modes[self._index]

    @property
    def all(self) -> list[Mode]:
        return list(self._modes)

    def set_by_id(self, mode_id: str):
        with self._lock:
            for i, m in enumerate(self._modes):
                if m.id == mode_id:
                    self._index = i
                    break
        self._notify()

    def cycle(self):
        with self._lock:
            self._index = (self._index + 1) % len(self._modes)
        self._notify()

    def on_change(self, callback):
        self._listeners.append(callback)

    def _notify(self):
        current = self.current
        for cb in self._listeners:
            try:
                cb(current)
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Config schema 驗證
# ---------------------------------------------------------------------------

def validate_config(config: dict) -> None:
    """驗證 config dict 結構。缺欄位或型別錯誤時拋出帶說明的 ValueError。"""
    modes = config.get("modes")
    if not modes or not isinstance(modes, list):
        raise ValueError("config.modes 必須為非空陣列")
    for i, m in enumerate(modes):
        if not isinstance(m, dict):
            raise ValueError(f"config.modes[{i}] 必須為物件")
        for field in ("id", "name"):
            if field not in m:
                raise ValueError(f"config.modes[{i}] 缺少必填欄位：{field!r}")

    api = config.get("api")
    if not isinstance(api, dict):
        raise ValueError("config.api 必須為物件")
    provider = api.get("provider", "")
    if provider not in ("grok", "openai", "groq"):
        raise ValueError(
            f"config.api.provider 必須為 grok / openai / groq，目前值：{provider!r}"
        )

    rec = config.get("recording", {})
    if not isinstance(rec.get("sample_rate"), int):
        raise ValueError("config.recording.sample_rate 必須為整數")
    if not isinstance(rec.get("channels"), int):
        raise ValueError("config.recording.channels 必須為整數")
    input_device = rec.get("input_device")
    if input_device is not None and not isinstance(input_device, (int, str, list)):
        raise ValueError("config.recording.input_device 必須為字串、整數、陣列或 null")


# ---------------------------------------------------------------------------
# 設定載入
# ---------------------------------------------------------------------------

def load_config() -> dict:
    """從 config.json 載入設定（支援新 schema + 向後相容舊 schema）"""

    _default_mode = {
        "id": "direct",
        "name": "直接轉錄",
        "icon": "📝",
        "language": "zh",
        "translate_to_english": False,
        "prompt": "請使用繁體中文。包含：蕭淳云, 周芷萓, 合作廠商加模, 專案 Tahoe, n8n, Zeabur。",
        "regex_rules": [
            {"pattern": r"N8n|N 8 n", "replacement": "n8n", "flags": "IGNORECASE"}
        ],
    }
    config = {
        "api": {
            "provider": "grok",
            "openai": {
                "api_key": "",
                "model": "gpt-4o-transcribe",
                "endpoint": "https://api.openai.com/v1/audio/transcriptions",
            },
            "grok": {
                "api_key": "",
                "model": "grok-stt",
                "endpoint": "https://api.x.ai/v1/stt",
            },
            "groq": {
                "api_key": "",
                "model": "whisper-large-v3-turbo",
                "endpoint": "https://api.groq.com/openai/v1/audio/transcriptions",
            },
            "temperature": 0.0,
        },
        "recording": {"sample_rate": 16000, "channels": 1, "input_device": None},
        "hotkey": {
            "record_key": "F1",
            "record_modifier": "ctrl",
            "mode_cycle_key": "F10",
            "mode_cycle_modifier": "ctrl",
        },
        "modes": [_default_mode],
        "default_mode_id": "direct",
        "vocab": {
            "enabled": False,
            "file": "user_vocab.json",
            "stt_keyterm_limit": 10,
            "match": {
                "use_tone": False,
                "require_surname_char_same": False,
                "min_term_len": 2,
            },
        },
        "ui": {
            "hud_enabled": True,
            "hud_position": "bottom-right",
            "hud_offset_x": 20,
            "hud_offset_y": 20,
            "hud_opacity": 0.9,
            "hud_font_size": 14,
        },
    }

    base = get_base_dir()
    config_paths = [
        base / "config.json",
        Path.home() / ".whisper-voice-typing" / "config.json",
    ]

    for cp in config_paths:
        if not cp.exists():
            continue
        with open(cp, encoding="utf-8") as f:
            user_cfg = json.load(f)

        if "modes" in user_cfg:
            config["modes"] = user_cfg["modes"]
            config["default_mode_id"] = user_cfg.get("default_mode_id", "direct")
            if "api" in user_cfg:
                api_u = user_cfg["api"]
                config["api"]["provider"] = api_u.get("provider", config["api"]["provider"])
                config["api"]["temperature"] = api_u.get("temperature", config["api"]["temperature"])
                for pname in ("openai", "grok", "groq"):
                    if pname in api_u:
                        config["api"][pname].update(api_u[pname])
                if "llm_correction" in api_u:
                    config["api"]["llm_correction"] = api_u["llm_correction"]
            if "recording" in user_cfg:
                config["recording"].update(user_cfg["recording"])
            if "hotkey" in user_cfg:
                config["hotkey"].update(user_cfg["hotkey"])
            if "ui" in user_cfg:
                config["ui"].update(user_cfg["ui"])
            if "vocab" in user_cfg:
                vocab_u = user_cfg["vocab"]
                config["vocab"]["enabled"] = vocab_u.get("enabled", config["vocab"]["enabled"])
                config["vocab"]["file"] = vocab_u.get("file", config["vocab"]["file"])
                config["vocab"]["stt_keyterm_limit"] = vocab_u.get(
                    "stt_keyterm_limit", config["vocab"]["stt_keyterm_limit"]
                )
                if "match" in vocab_u:
                    config["vocab"]["match"].update(vocab_u["match"])

        else:
            # 舊 schema fallback
            old_prompt = _default_mode["prompt"]
            old_regex = _default_mode["regex_rules"]
            old_lang = "zh"
            if "prompt" in user_cfg:
                old_prompt = user_cfg["prompt"].get("text", old_prompt)
            if "post_process" in user_cfg:
                old_regex = user_cfg["post_process"].get("regex_rules", old_regex)
            if "api" in user_cfg:
                old_lang = user_cfg["api"].get("language", old_lang)
                config["api"]["temperature"] = user_cfg["api"].get("temperature", 0.0)
                old_key = user_cfg["api"].get("openai_api_key", "")
                if old_key and old_key != "YOUR_OPENAI_API_KEY_HERE":
                    config["api"]["openai"]["api_key"] = old_key
                old_model = user_cfg["api"].get("model", "")
                if old_model:
                    config["api"]["openai"]["model"] = old_model
                config["api"]["provider"] = "openai"
            if "recording" in user_cfg:
                config["recording"].update(user_cfg["recording"])
            if "hotkey" in user_cfg:
                config["hotkey"]["record_key"] = user_cfg["hotkey"].get("record_key", "F1")
                config["hotkey"]["record_modifier"] = user_cfg["hotkey"].get("record_modifier", "ctrl")
                config["hotkey"]["mode_cycle_key"] = user_cfg["hotkey"].get("mode_cycle_key", "F10")
                config["hotkey"]["mode_cycle_modifier"] = user_cfg["hotkey"].get("mode_cycle_modifier", "ctrl")

            config["modes"] = [{
                **_default_mode,
                "language": old_lang,
                "prompt": old_prompt,
                "regex_rules": old_regex,
            }]
            config["default_mode_id"] = "direct"
        break

    # env.local / .env.local 覆蓋 API keys
    env_candidates = [
        base / "env.local",
        base / ".env.local",
        base.parent / "env.local",
        base.parent / ".env.local",
    ]
    for env_file in env_candidates:
        if env_file.exists():
            with open(env_file, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, _, value = line.partition("=")
                        os.environ.setdefault(key.strip(), value.strip())
            break

    if os.environ.get("OPENAI_API_KEY"):
        config["api"]["openai"]["api_key"] = os.environ["OPENAI_API_KEY"]
    if os.environ.get("XAI_API_KEY"):
        config["api"]["grok"]["api_key"] = os.environ["XAI_API_KEY"]
    if os.environ.get("GROQ_API_KEY"):
        config["api"]["groq"]["api_key"] = os.environ["GROQ_API_KEY"]

    return config
