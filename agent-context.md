# Agent Context

## Project Purpose
語音轉文字工具（Grok STT / OpenAI / Groq + Cerebras LLM，macOS 主力）。
approach-6 是唯一現役方案（macOS 26 相容）。approach-3 已封存（Windows，勿修改）。

## Runtime Profile
- Primary language: Python 3
- Virtual env: `approach-6-whisper-macos/.venv/`
- Config: `approach-6-whisper-macos/config.json`（schema 驗證：`_voice_config.validate_config()`）
- Secrets: `env.local`（project root，git-ignored，chmod 600）
- Log: `~/Library/Logs/WhisperVoice/app.log`

## Key Paths
| Path | Purpose |
|------|---------|
| `approach-6-whisper-macos/` | 唯一現役方案 |
| `approach-6-whisper-macos/INDEX.md` | 模組路由文件（讀此再鑽入程式碼） |
| `approach-3-python-exe/` | 封存方案（Windows，勿修改） |
| `env.local` | API keys（OPENAI / GROK / GROQ / CEREBRAS），git-ignored |
| `test_api_key.py` | 驗證 OpenAI / Grok / Groq 連線 |
| `test_cerebras.py` | 驗證 Cerebras 連線 |
| `todo.md` | 中/低優先未完成項目（NativeHUD、approach-7 等） |

## Scope Boundaries
- Prefer changes inside this project only.
- approach-3 is archived; do not modify unless explicitly requested.
- Use `INDEX.md` before reading raw source files in approach-6.
