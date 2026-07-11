# Agent Progress & Open Issues

## Recent Progress

### 2026-07-11 — 改名：approach-7 / WhisperVoice → VoiceKey

- **範圍**：目錄 `approach-7-xcode/` → `voicekey/`（git mv，保留歷史）；target/module/scheme `WhisperVoice` → `VoiceKey`；bundle id → `com.alston.VoiceKey`；簽章 identity → `"VoiceKey Self-Signed"`（`setup-signing-cert.sh` 已同步，需重跑一次）；`WHISPERVOICE_DD` / `WHISPERVOICE_ENV_FILE` → `VOICEKEY_DD` / `VOICEKEY_ENV_FILE`（env file 舊名仍向下相容）。
- **舊資料自動遷移**（首次啟動，皆不覆蓋既有新檔）：
  - App Support `WhisperVoice/` → `VoiceKey/`（詞彙檔、env.local、config.local.json 逐檔複製）
  - keychain：讀取時 fallback 舊 service `com.alston.WhisperVoice`
  - session DB：`~/.whisper_voice_log.db` → 複製為 `~/.voicekey_log.db`
- 舊 xcodeproj 生成物（含 iCloud 產生的 `WhisperVoice 2/3.xcodeproj`）已刪除，`VoiceKey.xcodeproj` 由 xcodegen 重新生成（本機已 `brew install xcodegen`）。
- 驗證：`xcodebuild test`（`CODE_SIGNING_ALLOWED=NO`）**34 tests green**。
- **待使用者**：① 跑 `bash voicekey/setup-signing-cert.sh` 建新憑證；② Release build 安裝 `/Applications/VoiceKey.app`、移除舊 `WhisperVoice.app`；③ 重新授權麥克風＋輔助使用（bundle id 變更，TCC 必掉，屬預期一次性成本）。

### 2026-07-11 — approach-7：STT keyterm merge 改為每次錄音動態合併（修正假熱重載）

- **問題**（源自 approach-6 review，原樣移植進 approach-7）：
  1. vocab / layer1 keyterms 只在啟動時 merge 進 `Mode.grokKeyterms` 一次 → 詞彙檔熱重載對 STT 層無效（文件宣稱「改檔不必重啟」與實際不符）。
  2. merge 順序為「mode 靜態 keyterms 優先」+ 截斷至 `stt_keyterm_limit`（10）→ direct 模式 config 已寫死 11 個 keyterms，user_vocab / layer1 的詞永遠擠不進 STT。
- **修法**（僅動 approach-7；approach-6 凍結不動，作為退路）：
  - `VocabStores.mergeKeyterms(into:)` 啟動時整批改寫 modes → 改為 `effectiveKeyterms(for:limit:)`，在 `VoiceController.processRecording` 每次錄音時動態計算（`maybeReloadAll()` 之後，故熱重載真正生效）。
  - 合併優先序改為 **user vocab（layer3）→ layer1 → mode 靜態 keyterms**，使用者維護的詞彙檔不再被靜態設定擠出。
  - `Mode.grokKeyterms` 語義改為「config 原始 base 值」，不再於啟動時被改寫。
- 測試：新增 `testMergeKeytermsUserVocabWinsOverStaticModeList`、`testMergeKeytermsDedupsAndSkipsEmpty`；**34 tests green**（`CODE_SIGNING_ALLOWED=NO` + `DEVELOPER_DIR` 指向 Xcode.app）。
- 決策記錄：approach-6 → approach-7 為最終遷移方向；approach-6 凍結、待 approach-7 穩定使用一段時間後刪除。所有後續改善只做在 approach-7。

### 2026-06-19 — 台灣口語數字轉半形阿拉伯數字 + approach-7 更新安裝

- approach-6 / approach-7 三個中文模式（direct / pro / casual）的 Cerebras `llm_prompt` 已同步加入數字格式規則：
  - 具體數值轉為半形阿拉伯數字；次數、序數、一般量詞保留中文。
  - 台灣口語省略：`四百一→410`、`兩千五→2500`、`三萬二→32000`。
  - 明說零時跳過位數：`四百零一→401`、`兩千零五→2005`、`三萬零二→30002`。
  - 明確禁止 LLM 改變數值、執行計算或回答原文問題。
- `ConfigMergeTests.testBundledConfigLoads` 新增三個中文模式的規則存在性驗證。
- 驗證：
  - 兩份 config JSON 合法且內容一致。
  - Cerebras 連線測試成功。
  - Xcode 單元測試：**32 tests green，1 live API test skipped**。
  - 以使用者原句直接實測 Cerebras，結果為「十次的零，然後一次300，一次410」，且未回答標準差。
- approach-7 Release 以 `CODE_SIGNING_ALLOWED=NO` 建置後 ad-hoc 簽章，`codesign --verify --deep --strict` 通過；已結束舊 approach-6 Python 程序、移除舊 `/Applications/WhisperVoice.app`、安裝新版並成功啟動，目前僅剩新原生版執行。
- 注意：ad-hoc rebuild 後 `AXIsProcessTrusted=false`，使用者需在「系統設定 → 隱私與安全性 → 輔助使用」重新開啟 WhisperVoice，才會恢復自動 Cmd+V；未授權時文字仍會留在剪貼簿。

### 2026-06-15 — voicekey：本機安裝完成（Xcode 26.5）

- 本機已確認存在完整 Xcode：`/Applications/Xcode.app`；`xcode-select` 仍指向 Command Line Tools，因此本次以 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 直接建置，未改全系統設定。
- 由於 `WhisperVoice Self-Signed` 憑證僅有 certificate、缺可用 codesigning identity，Release build 的正式簽章在 `CodeSign ... errSecInternalComponent` 失敗；本次改走 **ad-hoc** 路徑完成安裝，不阻塞使用。
- 驗證：
  - `xcodebuild -project WhisperVoice.xcodeproj -scheme WhisperVoice -configuration Release ... CODE_SIGNING_ALLOWED=NO build` 通過
  - `xcodebuild ... test CODE_SIGNING_ALLOWED=NO` 通過：**32 tests green，1 live API test skipped**
  - ad-hoc `codesign --force --deep --sign -` 後，`codesign --verify --deep --strict` 通過
  - 已以 `ditto` 安裝到 `/Applications/WhisperVoice.app`，並成功啟動（PID 73151）
- 本機設定：
  - `env.local` 已放到 `~/Library/Application Support/WhisperVoice/env.local`，權限 `600`
  - 首次啟動後 `layer1_keyterms.json`、`layer2_corrections.json`、`user_vocab.json` 已種到 App Support
- 注意：目前 `/Applications/WhisperVoice.app` 為 **ad-hoc** 簽章；若未來改用 self-signed 固定 identity，可避免 rebuild 後 Accessibility 授權掉失。

### 2026-06-15 — voicekey：建立可分發 zip / dmg

- 新增分發腳本：`voicekey/make-distribution.sh`
  - 來源預設取 `~/Library/Developer/WhisperVoice-DD-Adhoc/Build/Products/Release/WhisperVoice.app`
  - 產出到 `voicekey/dist/`
- 新增安裝說明與範例設定：
  - `voicekey/dist/INSTALL-zh-TW.md`
  - `voicekey/dist/env.local.example`
- 已產出：
  - `voicekey/dist/WhisperVoice-macOS-20260615.zip`
  - `voicekey/dist/WhisperVoice-macOS-20260615.dmg`
- 驗證：
  - `zip` 內容包含 `WhisperVoice.app`、`INSTALL-zh-TW.md`、`env.local.example`
  - `dmg` 掛載後內容正確，並附 `/Applications` 捷徑
  - 目前分發包內 App 仍為 **ad-hoc** 簽章；跨機首次需右鍵「開啟」或移除 quarantine

### 2026-06-14 — voicekey：修復錄音啟動卡死造成選單列無反應

#### 現象
- `/Applications/WhisperVoice.app` PID `83966` CPU 偏高；log 最後停在 `21:58:58 🔴 錄音中...`，沒有後續「錄音裝置 / 硬體格式 / WAV 已存」。
- `sample 83966` 顯示主執行緒卡在 `VoiceController.startRecording()` → `AudioRecorder.start()` → `AVAudioEngine.inputNode` / CoreAudio HAL 查詢，因此 AppKit event loop 被堵住，選單與「結束程式」也無反應。

#### 變更
- `AudioRecorder.start()` 改為回傳 Bool；啟動失敗會復原 `isRecording=false`。
- `VoiceController` 新增 `recordingQueue`，把 `recorder.start()` 與 `recorder.stop()` 放到同一個 serial queue，避免 CoreAudio 同步查詢卡住主執行緒。
- `GOTCHAS-xcode.md` 新增 1d：`AVAudioEngine.inputNode/inputFormat` 偶發卡住的症狀、根因與解法。

#### 處置與驗證
- 先以 `kill -TERM 83966` 正常結束卡住的舊 app。
- `./build.sh Release` 通過，已用 `ditto` 更新 `/Applications/WhisperVoice.app`。
- `codesign --verify --deep --strict --verbose=2 /Applications/WhisperVoice.app` 通過，簽章仍為 `WhisperVoice Self-Signed`。
- `./test.sh` 通過：32 tests green，live API test 依設定 skip。
- 已重新啟動 `/Applications/WhisperVoice.app`，新 PID `8466`；log 顯示熱鍵、麥克風、輔助使用皆授權成功。

### 2026-06-14 — voicekey：原生 Swift/AppKit 版（Phase 0→7 全數完成）

**一口氣完成 planxcode060614.md 全部 7 個 Phase，每個 Phase `xcodebuild` 通過。**

#### 成果
- 新建 `voicekey/`（與 approach-6 並排存活，OpenCC 層省略）。xcodegen（`project.yml`）+ `xcodebuild` headless build；ad-hoc 簽章。
- 模組對照 approach-6：`Config`(+config.local.json deep merge/schema)、`Mode/ModeManager`、`Secrets`(env→Keychain)、`AudioRecorder`(AVAudioEngine→16k mono PCM16 + CoreAudio 裝置選擇)、`HotkeyManager`(**Carbon RegisterEventHotKey，免「輸入監控」授權**)、`TranscribeProvider`(Grok/OpenAI/Groq)、`CerebrasProvider`(失敗降級不拋例外)、`RegexCorrections`、三層 `VocabStore`(+mtime 熱重載)、`PinyinEngine`(CFStringTransform)、`Paste`(NSPasteboard+CGEvent Cmd+V)、`MenuBarController`(狀態列+模式打勾+三層詞彙子選單)、`SessionLogger`(libsqlite3, ~/.whisper_voice_log.db, 600)、`SingleInstance`(flock)。
- 詞彙檔首次啟動由 bundle 種子到 `~/Library/Application Support/WhisperVoice/`（可編輯、存檔即熱重載）。

#### 驗證（headless，免麥克風/真人）
- **拼音引擎對拍 pypinyin**：CFStringTransform 與 pypinyin 完全一致（蕭淳云→xiao chun yun、周芷萓→zhou zhi yi、加模→jia mo，含罕用字 萓）。
- **32 單元測試綠**：Config 合併/schema、Grok/OpenAI multipart 組裝、Cerebras body+降級、`蕭純云→蕭淳云` fuzzy、override、require_surname、熱重載、壞檔降級、Layer1/2。
- **真實 API smoke test**（`say` 生成語音→真實 Grok STT→真實 Cerebras）通過：STT 回文字、Cerebras 修正大小寫生效。
- **執行驗證**：4 模式載入、USB 麥克風列舉+候選自動選中、Carbon 熱鍵註冊成功、麥克風/輔助使用授權、vocab 種子化（12 詞）、session DB 18 欄（含 vocab_out/llm_finish_reason）權限 600、單例鎖（第二實例退出）、ad-hoc `codesign --verify` 通過。

#### 待真人 / 已知問題（詳見 `voicekey/ISSUES-xcode.md`）
- 真人實機：按 Ctrl+F1 講中文、確認貼上+狀態列、Ctrl+F10/選單切模式。
- 獨立 `.app`（雙擊）需各自勾選麥克風/輔助使用（與從終端機繼承不同）。
- Gatekeeper 拒 ad-hoc（預期）：跨機右鍵→開啟或 `xattr -dr com.apple.quarantine`；notarization 需付費帳號，**日後選配**。
- DerivedData 不可放 iCloud 同步目錄（已固定到 `~/Library/Developer/WhisperVoice-DD`）。

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
