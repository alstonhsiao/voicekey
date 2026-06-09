# Agent Progress & Open Issues

## Recent Progress

### 2026-06-09 — approach-6-whisper-macos：浮動 HUD + 模式切換 + Grok API

**完成 Phases 0–9（plan20260609.md）**

#### 變更檔案
- `approach-6-whisper-macos/main.py`：重構（+約 350 行）
  - `load_config()` 重寫：支援新 schema + 向後相容舊 schema
  - 新增 `Mode` / `ModeManager` 類別（模式系統）
  - 新增 `TranscribeProvider` / `OpenAIProvider` / `GroqProvider` / `GrokProvider` + `build_provider()`（Provider 抽象）
  - 移除舊 `transcribe()` 函式
  - 新增 `HUD` 類別（tkinter 浮動視窗、點擊展開模式選單）
  - `main()` 重寫：注入 ModeManager、Provider、HUD；加入 F10 模式循環熱鍵
- `approach-6-whisper-macos/config.json`：重寫為新 schema（多模式、multi-provider）
- `approach-6-whisper-macos/main.py.bak` / `config.json.bak`：備份（不入 git）

#### 不變動的函式（依計畫保留）
`ensure_single_instance`, `try_start_menubar`, `set_menubar_state`,
`AudioRecorder`, `apply_corrections`, `paste_text`, `beep`

#### Grok STT API 驗證結論
- Endpoint: `POST https://api.x.ai/v1/stt`
- 欄位：`file`（最後）、`language`、`keyterm`（可重複，對應 prompt 關鍵字）
- 無 `model` 欄位；response: JSON `{"text":"...", "language":"...", "duration":N}`
- `prompt` 欄位不支援 → 改用 `keyterm` 傳遞關鍵詞

#### Phase 8 速度比較（5 秒語音 × 3 次）
| Provider | 平均回應時間 |
|---------|------------|
| Grok STT | **0.97s** |
| OpenAI gpt-4o-transcribe | 1.43s |
> Grok 比 OpenAI 快 ~32%，延遲更穩定（0.94–0.99s vs 0.87–2.05s）

---

## Open Issues / TODO
- [ ] Grok STT 傳統中文 keyterm 支援需更多實測（目前使用 TTS 生成音訊測試）
- [ ] 使用者實際錄音測試 HUD 三個狀態切換（需人工操作）
- [ ] 如需繁體中文輸出，可考慮 post-process 轉換（Grok 目前回簡體）

## Maintenance Note
- Update this file at end of each substantial task to avoid AGENTS.md growth.
