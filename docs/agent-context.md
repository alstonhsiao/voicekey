# Agent Context

## Project Purpose
語音轉文字工具（Grok STT / OpenAI / Groq + Cerebras LLM，macOS 主力）。
**VoiceKey**（`voicekey/`）為主力方案；前代 Python 方案已歸檔，歷史摘要見 `docs/archive/approach-6-macos.md`。

## Runtime Profile（VoiceKey）
- Primary language: Swift 5.9+（AppKit menu bar agent）
- Build: xcodegen + xcodebuild（見 `voicekey/build.sh`）
- Config: bundle `config.json` + `~/Library/Application Support/VoiceKey/config.local.json`
- Secrets: `~/Library/Application Support/VoiceKey/env.local` 或 Keychain
- Log: `~/Library/Logs/VoiceKey/app.log`
- Session DB: `~/.voicekey_log.db`

## Key Paths
| Path | Purpose |
|------|---------|
| `voicekey/` | 主力方案（VoiceKey 原生 App） |
| `voicekey/INDEX.md` | 建置、簽章、安裝（新 session 開工必讀） |
| `docs/INDEX.md` | Agent 文件路由索引 |
| `voicekey/GOTCHAS-xcode.md` | 錄音/簽章/選單列踩坑 |
| `voicekey/ISSUES-xcode.md` | 待真人/跨機項 |
| `scripts/INDEX.md` | 開發驗證腳本索引 |
| `docs/archive/INDEX.md` | 已完工歷史施工藍圖索引 |
| `env.local` | 開發用 API keys（project root，git-ignored） |
| `scripts/test_api_key.py` | 驗證 OpenAI / Grok / Groq 連線 |
| `scripts/test_cerebras.py` | 驗證 Cerebras 連線 |
| `todo.md` | 中/低優先未完成項目 |

## Scope Boundaries
- Prefer changes inside `voicekey/` unless explicitly working on frozen/archived approaches.
