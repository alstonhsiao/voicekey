# Agent Progress & Open Issues

## Recent Progress

### 2026-06-14 — 使用者自訂詞彙系統（第三層拼音 fuzzy 後處理）

**完成 plan20260614.md 全部施工項目**

#### 背景
- 人名/公司名可能超過 100 筆，塞不進 Grok keyterm（硬上限 10）與 LLM prompt（token 暴增）。
- STT 對中文人名常「音近字不同」（`蕭淳云`→`蕭純云`），純字面 regex 無法窮舉。

#### 變更
- 新增 `_voice_vocab.py`：`VocabStore` — 拼音索引 + `apply()` 替換引擎 + mtime 熱重載 + `load_vocab_store()`。
  - 比對策略：無聲調全拼音（`pypinyin` NORMAL）+ 同字數；`overrides` 字面替換最高優先。
  - 失敗一律降級回原文，絕不拋例外（比照 Cerebras fallback）。
- 新增 `user_vocab.json`：類別化詞彙（people / companies / projects / terms / overrides），從 config.json 遷移現有人名/術語。
- `config.json`：新增 `vocab` 區塊（`enabled` / `file` / `stt_keyterm_limit` / `match.{use_tone,require_surname_char_same,min_term_len}`）。
- `_voice_config.py`：`load_config()` 帶入 `vocab` 區塊預設值與覆蓋邏輯。
- `main.py`：import + init（log「詞彙修正：N 詞」）+ keyterm merge 進各 mode + 錄音前 `maybe_reload()` 熱重載 + pipeline 第三層插入（OpenCC 後、貼上前）+ session log 多記 `vocab_out`。
- `_voice_menubar.py`：新增「🗂 管理詞彙」子選單（路徑灰字顯示 + VSCode/預設 App/Finder 三動作，全 try/except）。`build_menubar_app()` 多收 `vocab_path`。
- `_voice_session.py`：migration 加 `vocab_out TEXT` 欄位。
- `requirements.txt`：加 `pypinyin==0.55.0`（實際安裝版本）。
- `INDEX.md` / `AGENTS.md`：記錄第三層架構。

#### 驗證
- `scripts/test_vocab.py` 三案例全過：`王之名`/`王之明`→`王志明`、`王大明` 不變；外加句中嵌入、overrides、已正確不重複改。
- 真實 config 整合測試：`蕭純云`→`蕭淳云`（拼音命中）、`家模公司`→`加模公司`（override）、keyterms 載入正確。
- `py_compile` 全數通過。
- 待使用者端到端錄音測試（見 plan §6）。

### 2026-06-13 — macOS 空辨識診斷

- 現象：YouTube Music 播放時啟動錄音，音樂聲音有變化，但 Grok STT 回傳空文字。
- log 結論：Grok STT HTTP 200 成功，`raw STT` 為空字串，非 API key / provider 連線錯誤。
- 音訊裝置：macOS 預設輸入/輸出皆為藍牙 `EJZZ EXJ-II`；開啟輸入串流會讓藍牙音訊切換/變化，這只代表麥克風通道被打開，不代表系統音訊被錄入。
- 實測：預設輸入錄 4 秒 RMS 約 `-53 dBFS`、peak 約 `-40 dBFS`，接近背景噪音，足以解釋 STT 判定無可辨識語音。
- 補查：系統設定截圖中的「語音控制 → 麥克風」是 Apple Voice Control 專用設定，不等於 sounddevice/CoreAudio 預設輸入。`USB Audio & HID` 可被程式指定為 input device，但直接錄 4 秒 RMS 約 `-76.8 dBFS`，仍接近靜音。
- 變更：`recording.input_device` 支援指定 input device，`config.json` 已設為 `USB Audio & HID`；錄音開始/停止會 log 實際裝置與 RMS/Peak。
- 下一步：若目標是轉錄 YouTube/系統聲音，需加入 loopback/虛擬音訊裝置（如 BlackHole）與 input device 選擇；若目標是口述，需確認麥克風輸入音量與裝置。

### 2026-06-12 — Security + Refactor（P0/P1/P2 完成）

- P0：`~/.whisper_voice_log.db` chmod 600；刪除重複根目錄 `.env.local`
- P1：WAV 暫存改隨機 NamedTemporaryFile；PID/lock 移至 `~/Library/Application Support/WhisperVoice/`；processing_flag 防 race condition；requirements.txt 全鎖版；install.sh 靜默讀 key + chmod 600；.command 改相對路徑；重啟腳本加 PID 比對防誤殺
- P2：approach-3 封存修正（build.bat 移除金鑰打包風險）；approach-6 main.py 拆 9 模組；logging 模組取代 print；config schema 驗證；test scripts 不印秘密字元；install_manual.md 補套件
- 詳見 git log：`edcbc22`、`dec3853`、`146ccc9`

---

### 2026-06-10 — approach-6-whisper-macos：繁體保險層 + debug log

#### 變更
- `approach-6-whisper-macos/requirements.txt`：
  - 新增 `opencc-python-reimplemented`，用於 LLM 後簡轉繁保險層。
- `approach-6-whisper-macos/main.py`：
  - 新增 OpenCC 載入與 `s2twp` 轉換器初始化。
  - 新增 `needs_traditional_normalization()` / `normalize_traditional_text()`，在 LLM 後偵測常見簡體字並做簡轉繁。
  - 新增 debug log：`raw STT`、`regex corrected`、`LLM corrected`、`normalized zh-TW`，便於判斷哪一層出了問題。
  - 英文翻譯模式 (`zh2en`) 不套用繁體正規化，避免誤傷英文輸出。

#### 驗證
- `./.venv/bin/python -m py_compile main.py` 通過。
- `opencc-python-reimplemented` 已安裝到 `approach-6-whisper-macos/.venv`。

### 2026-06-10 — approach-6-whisper-macos：自動貼上與模式切換可用性修正

#### 變更
- `approach-6-whisper-macos/main.py`：
  - `paste_text()` 改回以 AppleScript `activate + keystroke` 為主流程，符合既有 macOS 貼上治理做法。
  - 新增貼上 debug log：`paste target app` 與 `paste method`，方便判斷是授權問題還是焦點問題。
  - 新增 `mode_cycle_modifier`，將模式切換熱鍵改為 `Ctrl+F10`，避開 macOS 對單獨 `F10` 的常見攔截。
- `approach-6-whisper-macos/config.json`：
  - `hotkey.mode_cycle_modifier = "ctrl"`。
- `approach-6-whisper-macos/啟動語音輸入.command`：
  - 啟動前主動 `activate Terminal`，讓 debug log 視窗跳到前景。

#### 驗證
- `./.venv/bin/python -m py_compile main.py` 通過。

### 2026-06-10 — approach-6-whisper-macos：Cerebras LLM 雙層語音修正整合

**完成 Phases 0–5（plan20260610.md）**

#### 變更
- `approach-6-whisper-macos/config.json`：
  - 在 `api` 區塊下新增 `llm_correction` 設定，採用 `gpt-oss-120b` 作為 Cerebras 的預設大語言模型。
  - 為 `direct`、`zh2en`、`pro`、`casual` 模式新增 `grok_keyterms` 與 `llm_prompt`。
- `approach-6-whisper-macos/main.py`：
  - 新增 `LLMCorrectionProvider` 與其 `CerebrasProvider` 實作。
  - `CerebrasProvider` 採用 `requests` 庫直接調用 Cerebras API，避免安裝 `cerebras-cloud-sdk` 帶來的環境依賴衝突。
  - 實作 API 呼叫的 Fallback 邏輯（Cerebras 失敗時安全返回 STT 原始文字，不崩潰）。
  - 更新 `Mode` 類別以載入 `grok_keyterms` 與 `llm_prompt`，並實作向後相容。
  - 更新 `GrokProvider` 改為直接使用 `mode.grok_keyterms`。
  - 更新 `load_config`，支援讀取與複製 `llm_correction` 設定。
  - 重構 `_do_process_recording` 加入 LLM 修正與計時 Log（`⏱ STT: X.XXs | LLM: X.XXs | total: X.XXs`）。

#### 驗證
- 驗證 Cerebras API Key（`env.local` 讀取正常）。
- `test_cerebras.py` 測試通過（成功取得回覆「OK」）。
- 端對端單元測試：字間空格修正、繁簡轉換、標點補充、人名與術語修正符合預期。
- 429 Rate Limit/其他異常 Fallback 驗證：當遇到限制時安全返回 STT 原始文字，程式正常執行不崩潰。

---

### 2026-06-09 — approach-6-whisper-macos：macOS 26 相容性修正

**修復 macOS 26 (Tahoe) 啟動崩潰：停用 HUD + 重構 rumps 主執行緒**

#### 根因
- macOS 26 移除 `[NSApplication macOSVersion]` 與 `_setup:` selector
- Tk 8.5/9.0 在 `TkpGetColor → GetRGBA` 時呼叫已移除 API → SIGABRT
- rumps `NSApplication.run()` 必須在主執行緒，背景執行緒會丟 `NSWindow should only be instantiated on the main thread!`

#### 變更
- `config.json`：`ui.hud_enabled = false`
- `main.py`：
  - 移除 `try_start_menubar()`（背景執行緒架構）
  - 新增 `build_menubar_app(mode_manager)`：建立 rumps app 但不啟動，回傳給 main()
  - rumps 選單列加入四種模式切換與 `❌ 結束程式`
  - `main()` 結尾：pynput 改用 `listener.start()` 非阻塞，主執行緒呼叫 `rumps_app.run()`
  - `_probe_tkinter()` 加入 `Frame(bg=...)` + `Label(bg=...)` 測試以偵測 macOS 26 GetRGBA 崩潰
- `install_manual.md`：加入 macOS 26 Tahoe 系統需求註記與 FAQ
- `README.md`：更新 HUD 功能說明
- `todo.md`：標記 rumps 主執行緒重構完成

#### 驗證
- `.venv/bin/python main.py` 啟動 30 秒以上不崩潰，rumps 主執行緒事件迴圈正常

---

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
- [ ] Grok STT 傳統中文 keyterm 支援需更多實測（實際錄音測試，目前僅 TTS 生成音訊驗證）
- [ ] 使用者實際錄音測試各 mode 的 llm_prompt 效果（直接轉錄 / 專業模式 / 一般對話）
- [x] ~~如需繁體中文輸出，可考慮 post-process 轉換~~ → **已解決**：Cerebras LLM 第二層負責繁簡轉換

## Maintenance Note
- Update this file at end of each substantial task to avoid AGENTS.md growth.
