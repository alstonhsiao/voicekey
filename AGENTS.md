# AGENTS

> Governance Hub for this project. Read this file first in every new session.

## Mission
語音轉文字工具（Grok STT + Cerebras LLM，macOS 主力）。
**主力方案**：VoiceKey（`voicekey/`，原 approach-7 / WhisperVoice，2026-07-11 改名）— 原生 Swift/AppKit 版，34 單元測試綠。**本機實機已通過**（2026-07-12）：路徑 A 部署（`VoiceKey-macOS-20260712.dmg` → `/Applications`）+ 煙測 + 部署後驗證 #1 多 App 貼上、#2 模式切換。管線：錄音→Grok STT→Cerebras LLM→拼音詞彙→自動貼上。功能與 approach-6 對等（OpenCC 層省略）。bundle id `com.alston.VoiceKey`；舊 WhisperVoice 資料（App Support 詞彙檔、keychain、session DB）首次啟動自動遷移。其餘部署後驗證見 `todo.md`。
**分發**：`./package.sh && ./make-distribution.sh` → `voicekey/dist/VoiceKey-macOS-YYYYMMDD.{zip,dmg}`。**zip/dmg 不進 git**（本機產物，跨機用 AirDrop/USB 傳）；說明文件進 git：`voicekey/dist/INSTALL-zh-TW.md`。
**凍結方案（退路）**：approach-6（`approach-6-whisper-macos/`）— Python 版。**2026-07-11 起凍結不再修改**；所有改善只做在 VoiceKey。
**封存方案**：approach-3（`approach-3-python-exe/`）— Windows .exe，勿修改。
**架構**：Grok STT（第一層）→ Cerebras LLM（第二層修正）→ 拼音詞彙（第三層精修）。

## Always-On Rules
- **文件索引慣例**：僅專案根目錄可有 `README.md`；其餘資料夾以 `INDEX.md` 為路由索引（無內容需求可省略）。
- Keep this file concise: governance only; move details to spoke modules.
- Treat secrets and production credentials as strictly local and non-committable（`env.local` 永不進 git）。
- Prefer changes inside `voicekey/`；勿改 approach-6 / approach-3 unless explicitly requested.
- Prioritize high-risk constraints and validation steps before implementation.
- If requirement is unclear and risk is non-trivial, mark as `NEED_REVIEW` instead of guessing.
- **Repo 在 iCloud 目錄時**：`git status` / ahead-behind / `rev-list` 可能卡住；用 `git -c status.aheadBehind=false`，或在 `/tmp` 複本上 commit/push。

## Default Execution Flow
1. Read `AGENTS.md` (this file).
2. Open only the relevant spoke modules from the quick map.
3. For large directories, read their `INDEX.md` first, then drill down minimally.
4. After work, update `docs/agent-progress.md` and keep governance docs aligned.

## Quick Map
| Spoke | Path | When to Read |
|---|---|---|
| Docs Index | `docs/INDEX.md` | Agent 文件路由 — 讀此再鑽入 spoke。 |
| Context | `docs/agent-context.md` | Stack profile, key paths, current module overview. |
| Operations | `docs/agent-operations.md` | Non-negotiable rules, execution order, validation. |
| Progress | `docs/agent-progress.md` | Recent work, open TODOs. |
| Gotchas | `docs/agent-gotchas.md` | Known bugs, macOS quirks, API limits. |
| TODO | `todo.md` | 中/低優先未完成項。 |
| VoiceKey 安裝/建置 | `voicekey/INDEX.md` | 簽章、build、本機安裝、分發入口；新 session 開工必讀。 |
| 跨機安裝 | `voicekey/dist/INSTALL-zh-TW.md` | 目標 Mac 無需 Xcode 的安裝步驟。 |
| Xcode 踩坑 | `voicekey/GOTCHAS-xcode.md` | 錄音/簽章/build/選單列確認解法。動到這些前必讀。 |
| 待真人/跨機 | `voicekey/ISSUES-xcode.md` | 需真人操作或跨機驗證項。 |
| approach-6 退路 | `approach-6-whisper-macos/INDEX.md` | 僅查退路時讀；勿再改碼。 |
| Archived Plans | `docs/archive/INDEX.md` | 已完工施工藍圖（歷史參考）。 |

## Key Architecture Decisions
- **Grok STT 無 `prompt` 欄位**：用 `keyterm` 傳詞彙 hint；繁簡與修正交 Cerebras 第二層。
- **Cerebras fallback**：API 失敗降級回原始 STT，不崩潰。
- **VoiceKey 貼上**：NSPasteboard + CGEvent Cmd+V（需輔助使用授權）；Carbon 熱鍵免輸入監控。
- **簽章**：self-signed `VoiceKey Self-Signed`（`setup-signing-cert.sh`），避免 ad-hoc 每次 rebuild 掉輔助使用授權。未 notarize；跨機首次右鍵「開啟」。
- **config.local.json**：App Support deep merge，多機麥克風等本機覆蓋，不同步。
- **第三層拼音詞彙**：無聲調全拼音 + 同字數 fuzzy；mtime 熱重載；失敗降級原文。
- **DerivedData**：固定 `~/Library/Developer/VoiceKey-DD`（不可放 iCloud 同步的專案目錄內）。
- **approach-6 殘留決策**（僅退路）：macOS 26 貼上 osascript 主路徑；HUD 預設關；regex 僅 fallback。

## Escalation & Review
- `NEED_REVIEW`: conflicting specs, missing credentials, or potentially destructive changes.
- Keep historical details out of this hub; store them in spoke modules or archive.
