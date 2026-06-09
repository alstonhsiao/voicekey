# AGENTS

> Governance Hub for this project. Read this file first in every new session.

## Mission
語音轉文字工具（Grok STT / Whisper / Gemini，多平台）。
macOS 主力方案：approach-6（rumps 選單列、四模式切換、multi-provider；macOS 26 相容）。

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
| Context | `agent-context.md` | Project purpose, stack, boundaries, key paths. |
| Operations | `agent-operations.md` | High-impact rules, execution order, validation baseline. |
| Progress | `agent-progress.md` | Recent work, TODOs, unresolved items. |
| Refactor Report | `agent-refactor-report.md` | Phase 1+2 governance refactor record and metrics. |

## Escalation & Review
- `NEED_REVIEW`: conflicting specs, missing credentials, or potentially destructive changes.
- Keep historical details out of this hub; store them in spoke modules or legacy archive.
