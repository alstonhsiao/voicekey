# Agent Operations

## Non-Negotiable Rules
- 1. 在 `env.local`（或 `.env.local`）中加入 `GEMINI_API_KEY=你的Key`
- 確認專案根目錄的 `env.local`（或 `.env.local`）已有你的 Key：
- 2. 點選「Create new secret key」
- 按住 F9 不要放開  ← ── ── ── ──┐
- - 盡量說完整句子再放開，不要在句子中間放開
- 使用專案根目錄的 `test_api_key.py` 驗證 API Key 是否有效（**完全免費**，呼叫的是列出模型的端點，不消耗任何 token）：
- | `找不到 OPENAI_API_KEY` | 確認 `env.local`（或 `.env.local`）存在且格式正確 |
- 2. `env.local`（或 `.env.local`）檔案

## Execution Order
- Step 1: Read `AGENTS.md` and the quick map first.
- Step 2: Open only the module/index files relevant to the requested task.
- Step 3: Implement minimal safe changes, then validate with the project's native checks.

## Validation Baseline
- Confirm no secrets are exposed in code, logs, or commits.
- Confirm business-critical flows still pass smoke checks.
- Document assumptions in the final update when requirements are ambiguous.
