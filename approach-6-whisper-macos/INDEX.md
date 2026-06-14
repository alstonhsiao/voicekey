# approach-6-whisper-macos — Module Index

> Agent routing document. Read this before opening individual source files.
> One scan of this table replaces reading 11 modules to find the right one.

## Overview Table

| Module | ~KB | Purpose | Read When |
|--------|-----|---------|-----------|
| `main.py` | 13 | Entry point: init, hotkey, recording dispatch, rumps launch | Entry flow, startup issues |
| `_voice_config.py` | 10 | Config load, Mode/ModeManager, schema validation | Config changes, mode logic |
| `_voice_postprocess.py` | 8 | Regex corrections + OpenCC Traditional conversion | Post-processing changes |
| `_voice_vocab.py` | 9 | 三層詞彙 store：Layer1VocabStore / Layer2VocabStore / VocabStore + mtime 熱重載 | 任何詞彙層變更 |
| `layer1_keyterms.json` | <1 | 第一層使用者 Grok STT 額外關鍵詞（熱重載） | 加減 STT 關鍵詞 |
| `layer2_corrections.json` | <1 | 第二層使用者 LLM 修正詞彙（names + corrections，熱重載） | 加減 LLM 修正詞 |
| `user_vocab.json` | 1 | 第三層使用者拼音 fuzzy 詞彙（people/companies/projects/terms/overrides） | 加減人名、公司、術語 |
| `_voice_providers.py` | 6 | STT (Grok/OpenAI/Groq) + CerebrasProvider LLM | Provider / API changes |
| `_voice_hud.py` | 6 | tkinter HUD (disabled on macOS 26 by default) | HUD changes only |
| `_voice_paste.py` | 5 | osascript + GCD main-thread dispatch + paste_text | Paste / accessibility issues |
| `config.json` | 5 | Runtime config: api refs, modes, hotkey, ui flags | Config schema reference |
| `_voice_session.py` | 2 | SQLite session logger (chmod 600 on init) | Logging / DB issues |
| `_voice_menubar.py` | 3 | rumps menu bar: mode display, switch, 三層詞彙子選單, quit | Menu bar changes |
| `_voice_audio.py` | 2 | AudioRecorder: sounddevice + NamedTemporaryFile | Audio recording issues |
| `_voice_instance.py` | 1 | Single instance lock + PID file | Startup / lock issues |

## Module Notes

**main.py** — Slim entry point after P2 refactor. Wires all modules together.
⚠️ `rumps_app.run()` must be the last call in `main()` (macOS 26 main-thread requirement).
Hotkeys: Ctrl+F1 record toggle, Ctrl+F10 mode cycle.

**_voice_config.py** — `Mode` + `ModeManager` manage 4 modes: `direct / zh2en / pro / casual`.
Schema validation via `validate_config()` — missing keys raise friendly errors, not KeyError.

**_voice_providers.py** — ⚠️ Grok STT has no `prompt` field; uses `keyterm` list instead.
⚠️ Cerebras failure returns raw STT text, never raises.
Provider selection controlled by `config.json` `api.provider`.

**_voice_postprocess.py** — `apply_corrections()` is regex fallback only (not primary correction).
`normalize_traditional_text()` runs OpenCC `s2twp`; skipped for `zh2en` mode.

**_voice_vocab.py** — 第三層後處理，跑在 LLM + OpenCC 之後、貼上之前。
⚠️ 無聲調全拼音 + 同字數比對中文人名/公司名（`蕭純云`→`蕭淳云`）；不呼叫 API、詞彙無上限。
⚠️ 任何失敗一律降級回原文，絕不拋例外（比照 Cerebras fallback）。
`VocabStore.maybe_reload()` 以 mtime 熱重載 — 改 `user_vocab.json` 存檔即生效，不必重啟。
比對參數在 `config.json` 的 `vocab.match`（`use_tone` / `require_surname_char_same` / `min_term_len`）。
`overrides` 為字面強制替換（最高優先）；`terms`（英文/數字）不進拼音引擎，僅供 STT keyterms。

**_voice_paste.py** — ⚠️ pynput calls MUST be dispatched to GCD main thread on macOS 26 via `_run_on_main_thread()`.
Requires Terminal Accessibility permission for osascript (primary) path.

**_voice_hud.py** — Disabled by default (`hud_enabled: false`).
`_probe_tkinter()` detects macOS 26 crash signature via subprocess isolation.

**_voice_audio.py** — `processing_flag` blocks new recording while transcription is in progress.
WAV temp files use random names and are deleted after use.

**_voice_session.py** — Logs each transcription to `~/.whisper_voice_log.db`.
`os.chmod(DB_PATH, 0o600)` applied on every init.

**_voice_instance.py** — Lock file: `~/Library/Application Support/WhisperVoice/voice.lock`.
PID file used by `重啟語音輸入.command` restart script.

**config.json** — Structure: `api.providers` + `api.llm_correction` + `modes[]` + `vocab` + `hotkey` + `ui`.
⚠️ API keys are NOT stored here; loaded from `env.local` at startup.
