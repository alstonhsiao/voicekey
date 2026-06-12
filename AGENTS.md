# AGENTS

> Governance Hub for this project. Read this file first in every new session.

## Mission
語音轉文字工具（Grok STT + Cerebras LLM，macOS 主力）。
**現役方案**：approach-6（`approach-6-whisper-macos/`）— rumps 選單列、四模式切換、multi-provider、macOS 26 相容。
**封存方案**：approach-3（`approach-3-python-exe/`）— Windows .exe，暫時封存，勿修改。
**架構**：Grok STT（第一層）→ Cerebras LLM（第二層修正）— 解決繁簡混用、字間空格、術語辨識問題。

## Always-On Rules
- Keep this file concise: governance only; move details to spoke modules.
- Treat secrets and production credentials as strictly local and non-committable.
- Prioritize high-risk constraints and validation steps before implementation.
- If requirement is unclear and risk is non-trivial, mark as `NEED_REVIEW` instead of guessing.

## Default Execution Flow
1. Read `AGENTS.md` (this file).
2. Open only the relevant spoke modules from the quick map.
3. For large directories, read their `INDEX.md` first, then drill down minimally.
4. After work, update `agent-progress.md` and keep governance docs aligned.

## Quick Map
| Spoke | Path | When to Read |
|---|---|---|
| Context | `docs/agent-context.md` | Stack profile, key paths, current module overview. |
| Operations | `docs/agent-operations.md` | Non-negotiable rules, execution order, validation. |
| Progress | `docs/agent-progress.md` | Recent work, open TODOs, unresolved items. |
| Gotchas | `docs/agent-gotchas.md` | Known bugs, macOS quirks, API limits, confirmed fixes. |
| Code Index | `approach-6-whisper-macos/INDEX.md` | Module routing map — read before opening source files. |
| Refactor Report | `docs/agent-refactor-report.md` | Historical governance refactor record (archive). |

## Key Architecture Decisions
- **Grok STT 無 `prompt` 欄位**：用 `keyterm` 傳詞彙 hint；繁簡轉換與所有修正全交由 Cerebras LLM 第二層。
- **Cerebras fallback**：API 失敗時降級回原始 STT 文字，不崩潰。
- **macOS 26 貼上路徑**：主路徑 = osascript (Accessibility)；fallback = pynput 透過 GCD 主執行緒排程。
- **HUD 預設停用**：Tk 全系列在 macOS 26 不相容，`hud_enabled: false` 為安全預設值。
- **regex 不做主要修正**：`apply_corrections` 僅保留 fallback 兜底；主要修正全交 LLM 處理。

## Escalation & Review
- `NEED_REVIEW`: conflicting specs, missing credentials, or potentially destructive changes.
- Keep historical details out of this hub; store them in spoke modules or archive.
