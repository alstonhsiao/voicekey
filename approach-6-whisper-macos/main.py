"""
macOS 語音轉文字工具 — 方案六：Whisper / Grok STT（macOS）

使用方式：
  pip install -r requirements.txt
  python main.py

操作：
  - 按住 F9  → 開始錄音（聽到提示音後開始說話）
  - 放開 F9  → 停止錄音 → 自動辨識 → 貼上文字到游標位置
  - 按  F10  → 循環切換轉錄模式（直接轉錄 / 中翻英 / 專業模式 / 一般對話）
  - 點 HUD  → 展開模式選單（右下角浮動視窗）
  - HUD 右鍵 → 結束程式

macOS 權限需求：
  - 系統設定 → 隱私權與安全性 → 麥克風 → 允許 Terminal / IDE
  - 系統設定 → 隱私權與安全性 → 輔助使用 → 允許 Terminal / IDE
  - 系統設定 → 隱私權與安全性 → 輸入監控 → 允許 Terminal / IDE

API Provider：
  - 預設：xAI Grok STT（XAI_API_KEY in env.local）
  - 可在 config.json api.provider 切換：grok / openai / groq

與 approach-3（Windows Whisper）差異：
  - 針對 macOS 優化（提示音、Command+V、fcntl 單例鎖、rumps 選單列）
  - 加入浮動 HUD、多模式切換、API Provider 抽象
  - 無 winsound / Windows Mutex 依賴
"""

from __future__ import annotations

import logging
import os
import sys
import threading
import time
from pathlib import Path

import requests

from _voice_audio import AudioRecorder
from _voice_config import ModeManager, get_base_dir, load_config
from _voice_hud import HUD, _probe_tkinter
from _voice_instance import ensure_single_instance, remove_pid_file, write_pid_file
from _voice_menubar import build_menubar_app, set_menubar_state
from _voice_paste import beep, get_frontmost_app, paste_text
from _voice_postprocess import apply_corrections, normalize_traditional_text
from _voice_providers import build_llm_correction_provider, build_provider
from _voice_session import SessionLogger, _now
from _voice_vocab import load_vocab_store

# ---------------------------------------------------------------------------
# 日誌設定
# ---------------------------------------------------------------------------

_LOG_DIR = Path.home() / "Library" / "Logs" / "WhisperVoice"
_LOG_DIR.mkdir(parents=True, exist_ok=True)
_LOG_FILE = _LOG_DIR / "app.log"

_fmt = logging.Formatter("%(asctime)s %(levelname)-5s %(name)s: %(message)s",
                          datefmt="%H:%M:%S")

_file_handler = logging.FileHandler(_LOG_FILE, encoding="utf-8")
_file_handler.setFormatter(_fmt)

_console_handler = logging.StreamHandler(sys.stdout)
_console_handler.setFormatter(_fmt)

logging.basicConfig(level=logging.DEBUG, handlers=[_file_handler, _console_handler])
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# 主程式
# ---------------------------------------------------------------------------

def main():
    # ── 1. 防重複啟動 ──
    if not ensure_single_instance():
        sys.exit(0)
    write_pid_file()

    # ── 2. 載入設定 ──
    config = load_config()
    mode_manager = ModeManager(config["modes"], config["default_mode_id"])

    try:
        provider = build_provider(config["api"])
        llm_correction = build_llm_correction_provider(config["api"])
    except (RuntimeError, KeyError) as e:
        logger.error("❌ Provider 初始化失敗：%s", e)
        sys.exit(1)

    session_logger = SessionLogger()

    # ── 2b. 載入使用者自訂詞彙（第三層後處理）──
    base_dir = get_base_dir()
    vocab_store = load_vocab_store(base_dir, config)
    vocab_path = base_dir / config.get("vocab", {}).get("file", "user_vocab.json")
    if vocab_store:
        logger.info("   詞彙修正：%d 詞", len(vocab_store.stt_keyterms))
        # 把 vocab 詞 merge 進每個 mode 的 grok_keyterms（去重後截斷）
        try:
            limit = int(config.get("vocab", {}).get("stt_keyterm_limit", 10))
            for mode in mode_manager.all:
                merged: list[str] = []
                seen: set[str] = set()
                for kw in list(mode.grok_keyterms) + vocab_store.stt_keyterms:
                    if kw and kw not in seen:
                        seen.add(kw)
                        merged.append(kw)
                mode.grok_keyterms = merged[:limit]
        except Exception as e:
            logger.warning("⚠️  STT keyterm merge 失敗，沿用原 keyterms（%s）", e)

    # ── 3. 建立 rumps app（不啟動，稍後在主執行緒執行）──
    rumps_app = build_menubar_app(mode_manager, vocab_path=vocab_path)

    # ── 4. HUD ──
    hud = None
    if config["ui"]["hud_enabled"]:
        if _probe_tkinter():
            hud = HUD(mode_manager, config["ui"], on_quit=lambda: (remove_pid_file(), os._exit(0)))
            hud.start()
        else:
            logger.warning("⚠️  HUD 已停用：tkinter 無法初始化（Tk 版本與 macOS 不相容）")
            logger.warning("   修復方式：brew install python-tk@3.14")

    def set_state(s: str):
        set_menubar_state(s)
        if hud:
            hud.set_state(s)

    # ── 5. 初始化錄音 ──
    recorder = AudioRecorder(
        sample_rate=config["recording"]["sample_rate"],
        channels=config["recording"]["channels"],
        input_device=config["recording"].get("input_device"),
    )
    recording_flag = False
    processing_flag = False  # True = 辨識進行中，擋住新錄音避免 race condition
    lock = threading.Lock()

    # ── 6. 熱鍵偵測 ──
    from pynput import keyboard

    hotkey_map = {
        f"f{i}": getattr(keyboard.Key, f"f{i}")
        for i in range(1, 21) if hasattr(keyboard.Key, f"f{i}")
    }
    record_key      = hotkey_map.get(config["hotkey"]["record_key"].lower(), keyboard.Key.f1)
    cycle_key       = hotkey_map.get(config["hotkey"]["mode_cycle_key"].lower(), keyboard.Key.f10)
    record_modifier = config["hotkey"].get("record_modifier", "").lower()
    cycle_modifier  = config["hotkey"].get("mode_cycle_modifier", "ctrl").lower()

    _mod_display       = f"{record_modifier.upper()}+" if record_modifier else ""
    _key_display       = config["hotkey"]["record_key"].upper()
    hotkey_display     = f"{_mod_display}{_key_display}"
    _cycle_mod_display = f"{cycle_modifier.upper()}+" if cycle_modifier else ""
    cycle_hotkey_display = f"{_cycle_mod_display}{config['hotkey']['mode_cycle_key'].upper()}"

    logger.info("=" * 50)
    logger.info("🎤 Whisper 語音轉文字工具已啟動（macOS）")
    logger.info("   錄音熱鍵：%s（按一下開始，再按一下停止）", hotkey_display)
    logger.info("   切換模式：%s 或點 HUD", cycle_hotkey_display)
    logger.info("   Provider：%s", provider.name)
    if llm_correction:
        llm_model = config["api"].get("llm_correction", {}).get(llm_correction.name, {}).get("model", "unknown")
        logger.info("   LLM 修正：%s（%s）", llm_correction.name, llm_model)
    else:
        logger.info("   LLM 修正：停用")
    logger.info("   目前模式：%s", mode_manager.current.display)
    logger.info("   結束：選單列 ❌ 結束程式 或 Ctrl+C")
    logger.info("=" * 50)

    _MODIFIER_KEYS = {
        "ctrl":  (keyboard.Key.ctrl_l, keyboard.Key.ctrl_r, keyboard.Key.ctrl),
        "shift": (keyboard.Key.shift_l, keyboard.Key.shift_r, keyboard.Key.shift),
        "alt":   (keyboard.Key.alt_l, keyboard.Key.alt_r, keyboard.Key.alt),
    }
    _pressed_mods: set[str] = set()

    def _modifier_ok() -> bool:
        return not record_modifier or record_modifier in _pressed_mods

    def _cycle_modifier_ok() -> bool:
        return not cycle_modifier or cycle_modifier in _pressed_mods

    def _do_start_recording():
        if vocab_store:
            vocab_store.maybe_reload()  # 熱重載：改檔不必重啟
        set_state("recording")
        logger.info("🔴 錄音中... [模式：%s]（再按 %s 停止）", mode_manager.current.display, hotkey_display)
        recorder.start()
        for _ in range(60):
            time.sleep(0.05)
            if recorder.buffer_samples > 4000:
                beep()
                break

    def _do_process_recording(target_app: str = ""):
        nonlocal processing_flag
        wav_path, audio_sec = recorder.stop()
        try:
            if not wav_path:
                set_state("idle")
                logger.warning("⚠️  錄音時間太短，已忽略")
                return

            set_state("processing")
            mode = mode_manager.current
            logger.info("🔄 辨識中... [%s]", mode.display)

            t0 = time.time()
            try:
                raw_text = provider.transcribe(wav_path, mode)
            except requests.HTTPError as e:
                status = e.response.status_code if e.response else "?"
                msg = {401: "API Key 無效", 403: "API Key 權限不足", 429: "請求過於頻繁"}.get(
                    status, f"API 錯誤 HTTP {status}"
                )
                logger.error("❌ %s", msg)
                set_state("error")
                session_logger.log(
                    timestamp=_now(), mode_id=mode.id, mode_name=mode.name,
                    provider=provider.name, audio_sec=round(audio_sec, 2),
                    error_type="http_error", error_detail=f"HTTP {status}: {msg}",
                )
                time.sleep(2)
                set_state("idle")
                return
            except requests.exceptions.Timeout:
                logger.error("❌ 網路逾時")
                set_state("error")
                session_logger.log(
                    timestamp=_now(), mode_id=mode.id, mode_name=mode.name,
                    provider=provider.name, audio_sec=round(audio_sec, 2),
                    error_type="timeout", error_detail="requests.Timeout",
                )
                time.sleep(2)
                set_state("idle")
                return
            except Exception as e:
                logger.error("❌ 發生錯誤：%s", e)
                set_state("error")
                session_logger.log(
                    timestamp=_now(), mode_id=mode.id, mode_name=mode.name,
                    provider=provider.name, audio_sec=round(audio_sec, 2),
                    error_type="unknown", error_detail=str(e),
                )
                time.sleep(2)
                set_state("idle")
                return

            t_stt = time.time()
            stt_ms = int((t_stt - t0) * 1000)
            logger.debug("🪵 raw STT: %s", raw_text)

            corrected_text = apply_corrections(raw_text, mode.regex_rules)
            if not corrected_text:
                logger.warning("⚠️  辨識結果為空")
                set_state("idle")
                return
            logger.debug("🪵 regex corrected: %s", corrected_text)

            t_llm = time.time()
            llm_finish_reason = None
            if llm_correction and mode.llm_prompt:
                llm_corrected_text = llm_correction.correct(corrected_text, mode)
                llm_finish_reason = getattr(llm_correction, "last_finish_reason", None)
                logger.debug("🪵 LLM corrected: %s", llm_corrected_text)
            else:
                llm_corrected_text = corrected_text
                logger.debug("🪵 LLM corrected: <skipped>")
            llm_ms = int((time.time() - t_llm) * 1000)

            final_text = normalize_traditional_text(llm_corrected_text, mode)

            # ── 第三層：使用者自訂詞彙拼音 fuzzy 替換（失敗降級不崩潰）──
            vocab_out = None
            if vocab_store:
                vocab_out = vocab_store.apply(final_text)
                if vocab_out != final_text:
                    logger.debug("🪵 vocab corrected: %s", vocab_out)
                final_text = vocab_out

            logger.info("⏱  STT: %dms  |  LLM: %dms  |  total: %dms",
                        stt_ms, llm_ms, int((time.time() - t0) * 1000))

            paste_method, paste_ok = paste_text(final_text, target_app)
            logger.info("✅ 已貼上：%s", final_text)
            set_state("idle")

            session_logger.log(
                timestamp=_now(),
                mode_id=mode.id,
                mode_name=mode.name,
                provider=provider.name,
                audio_sec=round(audio_sec, 2),
                raw_stt=raw_text,
                regex_out=corrected_text,
                llm_out=llm_corrected_text if (llm_correction and mode.llm_prompt) else None,
                vocab_out=vocab_out,
                final_text=final_text,
                stt_ms=stt_ms,
                llm_ms=llm_ms if (llm_correction and mode.llm_prompt) else None,
                paste_method=paste_method,
                paste_ok=int(paste_ok),
                llm_finish_reason=llm_finish_reason,
            )
        finally:
            if wav_path:
                try:
                    os.unlink(wav_path)
                except OSError:
                    pass
            with lock:
                processing_flag = False

    def on_press(key):
        nonlocal recording_flag, processing_flag

        for mod_name, mod_keys in _MODIFIER_KEYS.items():
            if key in mod_keys:
                _pressed_mods.add(mod_name)
                return

        if key == cycle_key and _cycle_modifier_ok():
            mode_manager.cycle()
            logger.info("🔀 模式 → %s", mode_manager.current.display)
            return

        if key != record_key or not _modifier_ok():
            return

        with lock:
            if not recording_flag:
                if processing_flag:
                    logger.warning("⚠️  辨識進行中，請稍後再錄音")
                    return
                recording_flag = True
                threading.Thread(target=_do_start_recording, daemon=True).start()
            else:
                recording_flag = False
                processing_flag = True
                target_app = get_frontmost_app()
                threading.Thread(target=_do_process_recording, args=(target_app,), daemon=True).start()

    def on_release(key):
        for mod_name, mod_keys in _MODIFIER_KEYS.items():
            if key in mod_keys:
                _pressed_mods.discard(mod_name)
                return

    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()

    # 主執行緒執行 NSApplication 事件迴圈
    # macOS 26 要求 NSApplication（rumps）必須在主執行緒
    if rumps_app:
        try:
            rumps_app.run()
        except KeyboardInterrupt:
            pass
        finally:
            remove_pid_file()
    else:
        try:
            listener.join()
        except KeyboardInterrupt:
            pass
        finally:
            remove_pid_file()


if __name__ == "__main__":
    main()
