# Plan — WhisperVoice Xcode 原生版（approach-7-xcode）

> 建立日期：2026-06-14
> 目標：把現役 Python 方案（approach-6）重寫為原生 Swift / AppKit macOS App，
> 與 Python 版**並排存活**（side-by-side），失敗可隨時退回 Python。
> 本文件供「新 session」逐階段執行；新 session 開工前**必讀**本檔 + `AGENTS.md`。

---

## 0. 決策前提（已與使用者確認，2026-06-14）

| 項目 | 決定 |
|---|---|
| 功能範圍 | 與 approach-6 **完全對等**，不增不減（使用者已確認） |
| OpenCC 繁化層 | **省略**（使用者已同意）。理由：Cerebras LLM prompt 已含「輸出繁體中文」，實測簡體問題由 LLM 解決 |
| 並排存活 | Python（approach-6）保持不動；Xcode 版放在 `approach-7-xcode/` |
| 退場機制 | 若 Xcode 版失敗，整個 `approach-7-xcode/` 刪除即可，Python 版零影響 |
| config.local.json | 一併實作（Handoff20260614.md 的多台 Mac 需求） |

---

## 1. 為什麼做原生版（價值與代價）

**價值**
- 多機部署乾淨：拖一個 `.app` 進 `/Applications` 就裝好，不需 venv / pip / Terminal 授權
- 不怕 macOS 升版弄壞 Python 依賴（pynput / rumps / sounddevice 都曾因 macOS 26 出問題）
- 閒置記憶體更低（Python 版實測 149MB；原生預期 < 40MB）
- **全局熱鍵可改用 Carbon `RegisterEventHotKey`，免「輸入監控」授權**（Python pynput 需要）

**代價**
- 改邏輯要重新編譯（詞彙 JSON 仍可熱重載，不受影響）
- 重寫工時：預估 2–4 週（本 plan 拆成 7 個 Phase 降低風險）
- 拼音引擎要改用 `CFStringTransform`（pypinyin 無 Swift 對應）— 見 §4.7
- 需處理 code signing / notarization 才能在其他 Mac 免「來路不明」警告

---

## 2. App 形態與技術選型總表

| 面向 | Python（approach-6） | Xcode 版（approach-7）選型 | 備註 |
|---|---|---|---|
| App 類型 | Terminal 跑 script | **Menu bar agent app**（`LSUIElement=YES`，無 Dock 圖示） | |
| UI 框架 | rumps | **AppKit `NSStatusItem`**（非 SwiftUI MenuBarExtra） | 動態改 title 最直接，對齊 rumps 行為 |
| 語言 | Python 3 | **Swift 5.9+**，target macOS 13+ | |
| 全局熱鍵 | pynput（需輸入監控） | **Carbon `RegisterEventHotKey`**（推薦，免輸入監控授權） | 退路：CGEventTap（需輔助使用） |
| 錄音 | sounddevice | **AVAudioEngine** + `AVAudioFile` 寫 WAV | |
| 裝置選擇 | sounddevice query | **CoreAudio** `AudioObjectGetPropertyData` 依名稱比對 | 對齊 Python 的候選清單邏輯 |
| STT/LLM HTTP | requests | **URLSession**（multipart + JSON） | |
| 貼上 | pyperclip + osascript + pynput | **NSPasteboard** + **CGEvent** 合成 Cmd+V | 需輔助使用授權 |
| 前景 App | osascript | **NSWorkspace.frontmostApplication** | |
| 繁簡轉換 | OpenCC | **省略** | 見 §0 |
| 拼音 | pypinyin | **`CFStringTransform`**（mandarinLatin + stripDiacritics） | 見 §4.7 |
| 詞彙熱重載 | mtime 檢查 | **mtime 檢查**（錄音開始時），對齊 Python | |
| Session log | sqlite3 (Python stdlib) | **libsqlite3**（C API 直呼，零外部依賴） | 退路：GRDB.swift（SPM） |
| 單例鎖 | fcntl flock | **`NSRunningApplication` bundleId 檢查** 或 flock | |
| 設定檔 | config.json | config.json + **config.local.json** 覆蓋 | 見 §4.2 |
| API Key | env.local | env.local（相容）+ **Keychain**（.app 分發推薦） | 見 §4.3 |

---

## 3. 目錄結構（approach-7-xcode/）

```
approach-7-xcode/
├── WhisperVoice.xcodeproj
├── WhisperVoice/
│   ├── WhisperVoiceApp.swift          # @main NSApplicationMain / AppDelegate 掛載
│   ├── AppDelegate.swift              # 生命週期、單例鎖、組裝所有元件
│   ├── Info.plist                     # LSUIElement=YES、NSMicrophoneUsageDescription
│   ├── WhisperVoice.entitlements      # 無沙盒（見 §6）
│   │
│   ├── Core/
│   │   ├── Config.swift               # config.json + config.local.json deep merge + schema 驗證
│   │   ├── Mode.swift                 # Mode struct + ModeManager（執行緒安全）
│   │   ├── Secrets.swift              # API key：env.local → Keychain → config
│   │   ├── AppLog.swift               # os.Logger 包裝，寫 ~/Library/Logs/WhisperVoice/
│   │   └── SessionLogger.swift        # libsqlite3，~/.whisper_voice_log.db，chmod 600
│   │
│   ├── Audio/
│   │   └── AudioRecorder.swift        # AVAudioEngine 錄音 + CoreAudio 裝置選擇 + WAV 輸出
│   │
│   ├── Hotkey/
│   │   └── HotkeyManager.swift        # RegisterEventHotKey 包裝：record toggle / mode cycle
│   │
│   ├── Providers/
│   │   ├── TranscribeProvider.swift   # protocol + Grok / OpenAI / Groq
│   │   └── LLMCorrectionProvider.swift# protocol + Cerebras（失敗降級回原文）
│   │
│   ├── PostProcess/
│   │   ├── RegexCorrections.swift     # NSRegularExpression fallback 兜底
│   │   └── VocabStore.swift           # 三層詞彙：Layer1 / Layer2 / 拼音 fuzzy（第三層）
│   │
│   ├── Pinyin/
│   │   └── PinyinEngine.swift         # CFStringTransform 無聲調全拼音
│   │
│   ├── Paste/
│   │   └── Paste.swift                # beep + frontmost app + NSPasteboard + CGEvent Cmd+V
│   │
│   ├── MenuBar/
│   │   └── MenuBarController.swift    # NSStatusItem：狀態 title、模式選單、三層詞彙子選單、結束
│   │
│   └── Resources/
│       ├── config.json                # 從 approach-6 複製（去掉 OpenCC 相關）
│       ├── user_vocab.json            # 第三層
│       ├── layer1_keyterms.json       # 第一層
│       └── layer2_corrections.json    # 第二層
│
├── WhisperVoiceTests/
│   ├── PinyinEngineTests.swift        # 對拍 pypinyin 關鍵案例（蕭淳云 等）
│   ├── VocabStoreTests.swift          # fuzzy 替換、overrides、同字數比對
│   ├── ConfigMergeTests.swift         # config.local.json deep merge
│   └── ProviderTests.swift            # multipart 組裝、降級行為（mock URLSession）
│
└── README.md                          # 安裝、簽章、授權、與 Python 版差異
```

---

## 4. 模組逐一設計（Python → Swift 對照）

### 4.1 Mode / ModeManager（對應 `_voice_config.py`）

- `Mode` 為 `struct`：`id, name, icon, language, translateToEnglish, prompt, regexRules, grokKeyterms, llmPrompt`
- `ModeManager` 為 `final class`：`current`、`all`、`setById`、`cycle`、`onChange` callback
  - 用 `NSLock` 或 serial `DispatchQueue` 保護 index（對齊 Python 的 `threading.Lock`）
- 四個模式直接讀 config.json 的 `modes[]`，**不要 hardcode**

### 4.2 Config 載入 + config.local.json（對應 `_voice_config.py` + Handoff 需求）

讀取與覆蓋順序：
```
1. Bundle 內 Resources/config.json（共用預設，隨 .app 走）
   ─或─ 同步資料夾的 config.json（若使用者指定外部路徑）
2. ~/Library/Application Support/WhisperVoice/config.local.json（本機覆蓋，不同步）
3. deep merge：local 的值覆蓋 base 的對應值
```
- deep merge：dict 遞迴合併，陣列/純值直接以 local 取代
- schema 驗證：缺 `modes`、`api.provider` 不在 grok/openai/groq、`recording.sample_rate` 非整數 → 拋帶說明錯誤（對齊 `validate_config`）
- `recording.input_device` 支援 `字串 / 整數 / 陣列 / null`（陣列＝候選清單，依序找第一個存在的裝置）

### 4.3 Secrets（API Key）

優先序（對齊 README「API Key 優先順序」）：
```
1. 環境變數（OPENAI_API_KEY / XAI_API_KEY / GROQ_API_KEY / CEREBRAS_API_KEY）
2. env.local / .env.local（專案根或 Bundle 旁；.app 分發時讀 ~/Library/Application Support/WhisperVoice/env.local）
3. Keychain（推薦給 .app 分發：首次啟動引導輸入，存 kSecClassGenericPassword）
4. config.json 的 api_key 欄位
```
- ⚠️ key **絕不**進 git、絕不打包進 .app Resources

### 4.4 AudioRecorder（對應 `_voice_audio.py`）

- `AVAudioEngine` inputNode 裝 tap → 累積 buffer
- 取樣率 16000 / mono / 16-bit PCM → 用 `AVAudioFile` 或 `AVAudioConverter` 輸出 WAV 到 `NSTemporaryDirectory()` 隨機檔名，辨識後刪除
- 裝置選擇：CoreAudio `kAudioHardwarePropertyDevices` 列舉 → 比對名稱（exact → partial，對齊 `_find_device_by_name`）→ 支援候選清單
- `< 0.5s` 忽略不送 API（對齊 Python）
- 錄音開始後等 buffer 累積到門檻 → `beep()` 提示（對齊 Python 的 4000 samples）

### 4.5 HotkeyManager（對應 main.py 熱鍵段）

- **首選 Carbon `RegisterEventHotKey`**：
  - record toggle：Ctrl+F1（`controlKey` + `kVK_F1`）
  - mode cycle：Ctrl+F10（`controlKey` + `kVK_F10`）
  - callback 用 `InstallEventHandler` 接 `kEventHotKeyPressed`
  - **優點：不需「輸入監控」授權**
- 從 config.json `hotkey` 讀鍵位與修飾鍵；建一個 keyName → keycode 對照表（F1–F20）
- 退路（若 Carbon 不敷使用）：CGEventTap（需輔助使用授權）

### 4.6 Providers（對應 `_voice_providers.py`）

- `protocol TranscribeProvider { func transcribe(wavURL:, mode:) async throws -> String }`
  - **Grok**：multipart，欄位 `language` + 重複 `keyterm`（≤10 個、每個 ≤50 字元）+ `file`（最後）；回 JSON `{"text":...}`
  - **OpenAI**：multipart，`model / language / temperature / response_format=text / prompt`；`translate_to_english` 時改打 `/translations` 端點並移除 `language`
  - **Groq**：同 OpenAI 格式
  - 工廠 `buildProvider(api:)`：缺 api_key 拋錯（對齊 Python）
- `protocol LLMCorrectionProvider { func correct(text:, mode:, extraSystemPrompt:) async -> String }`
  - **Cerebras**：JSON POST `/v1/chat/completions`，system = `mode.llmPrompt` + 第二層注入；`temperature=0`，`max_tokens` 讀 config
  - ⚠️ **任何失敗回傳原始 text，絕不拋例外**（對齊 `CerebrasProvider`），記錄 `finish_reason`
  - HTTP 401/403/429/timeout 分類錯誤訊息（對齊 main.py 的 except 區塊）

### 4.7 PinyinEngine（對應 pypinyin，**最大技術挑戰**）

- 用 Foundation 內建 `CFStringTransform`：
  ```swift
  // 1. 漢字 → 帶聲調拼音（含 diacritics）
  CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
  // 2. 去聲調
  CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
  // → 得到空格分隔、無聲調全拼音，對齊 pypinyin lazy_pinyin(style=NORMAL)
  ```
- 逐字轉換後 split 成 `[String]`（對齊 `_pinyin_of` 回傳 tuple）
- ⚠️ **風險**：CFStringTransform 對多音字的選字可能與 pypinyin 不同。
  - 緩解：`PinyinEngineTests.swift` 用 `user_vocab.json` 實際人名（蕭淳云、周芷萓 等）對拍；
  - 若某字差異導致 fuzzy 失效，加一張 `overrides`（字面替換，最高優先）即可繞過，不阻塞。

### 4.8 VocabStore 三層（對應 `_voice_vocab.py`）

完全照搬 Python 三層語意：
- **第一層** `layer1_keyterms.json`：`keyterms[]` → 併入各 mode 的 grokKeyterms（去重、截斷到 `stt_keyterm_limit`）
- **第二層** `layer2_corrections.json`：`names[] + corrections{}` → `buildInjection()` 動態注入 LLM system prompt
- **第三層** `user_vocab.json`：
  - 類別 `people / companies / projects` 進拼音 fuzzy；`terms` 只供 STT keyterms
  - 索引 key = `(字數, 拼音tuple)` → canonical
  - `apply()`：先 `overrides` 字面替換 → 再拼音 fuzzy（同字數視窗滑動、`claimed` 防重疊、由長到短、由後往前替換）
  - 比對參數：`use_tone / require_surname_char_same / min_term_len`
- 三層全部 **mtime 熱重載**：在「錄音開始」時各 call `maybeReload()`（對齊 `_do_start_recording`）
- ⚠️ **任何失敗一律降級回原文，絕不拋例外**

### 4.9 Paste（對應 `_voice_paste.py`）

- `beep()`：`NSSound(named: "Tink")?.play()` 或 `afplay`
- 前景 App：`NSWorkspace.shared.frontmostApplication`（取代 osascript，更快更穩）
- 貼上：
  ```
  1. NSPasteboard.general.clearContents() + setString(text)
  2. 啟用目標 App（NSRunningApplication.activate）
  3. 合成 Cmd+V：CGEvent keyDown/keyUp（kVK_ANSI_V + maskCommand）post 到 .cghidEventTap
  ```
  - ⚠️ CGEvent 合成按鍵需 **輔助使用授權**（與 Python osascript 路徑同一張授權）
  - fallback：留在剪貼簿，提示使用者手動 Cmd+V
- macOS 26 主執行緒注意：CGEvent post 在主執行緒做；錄音/辨識在背景 `Task`

### 4.10 MenuBarController（對應 `_voice_menubar.py`）

- `NSStatusItem`（`.variableLength`），title 顯示狀態：`⏸ 待機 / 🔴 錄音中 / 🔄 辨識中 / ⚠️ 錯誤`
- 選單：
  - 四個模式 `NSMenuItem`（點選 `setById`，目前模式打勾）
  - 分隔線
  - 三層詞彙子選單（每層：檔名、路徑灰字、「用 VSCode 開啟 / 用預設 App 開啟 / 在 Finder 顯示」）
  - 分隔線
  - ❌ 結束程式
- 開檔用 `NSWorkspace.open` / `NSWorkspace.selectFile`（取代 subprocess open）

### 4.11 SessionLogger（對應 `_voice_session.py`）

- `libsqlite3` C API，DB = `~/.whisper_voice_log.db`，`chmod 0o600`
- 同一張 `sessions` 表結構（含 `vocab_out`、`llm_finish_reason` 兩個後加欄位）
- 序列化寫入（serial DispatchQueue）

### 4.12 主流程組裝（對應 main.py）

```
按 Ctrl+F1（錄音中=false）→ 三層 maybeReload → 開始錄音 → beep
按 Ctrl+F1（錄音中=true） → 抓前景 App → 停止錄音 →
  Task {
    STT transcribe
    → regex fallback 修正
    → Cerebras LLM 修正（+ 第二層注入；失敗降級）
    → 第三層拼音 fuzzy（失敗降級）
    → Paste（NSPasteboard + CGEvent；失敗剩剪貼簿）
    → SessionLogger.log
  }
按 Ctrl+F10 → ModeManager.cycle
```
- `processingFlag` 擋住辨識中重複錄音（對齊 Python race-condition 防護）

---

## 5. 風險表

| 風險 | 等級 | 緩解 |
|---|---|---|
| CFStringTransform 多音字與 pypinyin 不一致 | 中 | 單元測試對拍實際人名；差異案例用 overrides 繞過 |
| Accessibility 授權綁定簽章 identity，重簽後重置 | 中 | 開發期固定簽章；README 寫明重簽要重新授權 |
| Carbon RegisterEventHotKey 與其他 App 熱鍵衝突 | 低 | 鍵位可由 config 改；衝突時換鍵 |
| 沙盒化會擋全局熱鍵/貼上/讀外部檔 | 高（若誤開） | **明確不開沙盒**；放棄上架 App Store（見 §6） |
| AVAudioEngine 取樣率與 16k 不符需轉換 | 低 | AVAudioConverter 轉成 16k mono PCM16 |
| 多機 config 路徑差異 | 中 | config.local.json 覆蓋（§4.2） |
| API key 誤打包進 .app | 高 | Resources 不放 key；CI/手動檢查 |

---

## 6. Code Signing / 授權 / 分發

- **不開 App Sandbox**（沙盒會擋全局熱鍵、跨 App 貼上、讀任意路徑詞彙檔）→ 不上 Mac App Store，走直接分發
- **Entitlements**：最小化；Info.plist 加 `NSMicrophoneUsageDescription`
- 需要的系統授權（首次啟動引導）：
  | 授權 | 用途 | 少了會怎樣 |
  |---|---|---|
  | 麥克風 | 錄音 | 無法錄音 |
  | 輔助使用 (Accessibility) | CGEvent 合成 Cmd+V | 辨識成功但不貼上 |
  | 輸入監控 | **若用 Carbon HotKey 則不需要**（相對 Python 是改善） | — |
- 分發：
  - 個人/自用：ad-hoc 簽章即可
  - 給其他 Mac mini：**Developer ID 簽章 + notarization**（`notarytool`）→ 免「來路不明」Gatekeeper 警告
- ⚠️ 重新簽章會使「輔助使用」授權失效，需重新勾選

---

## 7. 實作 Phase（新 session 逐階段執行，每階段可驗證）

> 每個 Phase 結束都要能 build 過 + 手動驗證該階段行為，再進下一階段。

**Phase 0 — 專案骨架**
- 建立 `approach-7-xcode/` Xcode 專案（menu bar agent，LSUIElement）
- AppDelegate 起一個 `NSStatusItem` 顯示 🎤；能結束程式
- ✅ 驗證：選單列出現圖示，可結束

**Phase 1 — Config + Mode + Secrets**
- Config.swift（含 config.local.json merge + schema 驗證）、Mode/ModeManager、Secrets
- 從 approach-6 複製 config.json / 三個詞彙 json 到 Resources
- ✅ 驗證：log 印出載入的模式數、provider、key 是否就緒

**Phase 2 — 熱鍵 + 錄音 + 存 WAV**
- HotkeyManager（Carbon）+ AudioRecorder（AVAudioEngine + 裝置選擇）
- Ctrl+F1 toggle 錄音，存出 WAV 到暫存，beep
- ✅ 驗證：按鍵錄音、能在 Finder 看到（暫不刪）正確 16k mono WAV、有 beep

**Phase 3 — STT + LLM Provider**
- TranscribeProvider（Grok/OpenAI/Groq）+ LLMCorrectionProvider（Cerebras）
- 串起：錄音 → STT → LLM → 印出最終文字（先不貼）
- ✅ 驗證：說一段話，log 看到 raw STT 與 LLM 修正後文字

**Phase 4 — 貼上 + 前景 App + 狀態列**
- Paste.swift（NSPasteboard + CGEvent）+ frontmost app + MenuBar 狀態 title
- ✅ 驗證：辨識完整貼到游標處；狀態列即時顯示 🔴/🔄/⏸

**Phase 5 — 三層詞彙 + 拼音引擎**
- PinyinEngine（CFStringTransform）+ VocabStore 三層 + mtime 熱重載
- 詞彙子選單（開檔）
- ✅ 驗證：「蕭純云」→「蕭淳云」；改 user_vocab.json 存檔即生效不重啟；單元測試綠

**Phase 6 — Session log + 模式選單 + 收尾**
- SessionLogger（sqlite）+ 模式選單打勾切換 + 單例鎖
- ✅ 驗證：`~/.whisper_voice_log.db` 有完整欄位；四模式可切換

**Phase 7 — 簽章 / 分發 / 文件**
- Developer ID 簽章 + notarization 流程跑通
- approach-7-xcode/README.md：安裝、授權、與 Python 差異、退場說明
- ✅ 驗證：拖到另一台 Mac mini 能啟動、授權後可用

---

## 8. 驗收標準（與 approach-6 對等）

- [ ] Ctrl+F1 toggle 錄音、Ctrl+F10 切模式
- [ ] 四模式行為與 Python 版一致
- [ ] Grok STT + Cerebras LLM 串接，失敗降級不崩潰
- [ ] 三層詞彙：keyterms 注入 / LLM 注入 / 拼音 fuzzy 替換都生效
- [ ] 詞彙 JSON 改檔不重啟即生效
- [ ] 貼上到任意前景 App（需輔助使用授權）
- [ ] 選單列狀態即時、模式選單、詞彙開檔
- [ ] Session log 寫入 SQLite
- [ ] config.local.json 多機覆蓋可運作
- [ ] 閒置記憶體明顯低於 Python 版（目標 < 40MB）
- [ ] 簽章 + notarization 後可在第二台 Mac 直接執行

---

## 9. 並排存活 / 退場

- Python 版（`approach-6-whisper-macos/`）整段**不動**，隨時可回去用
- 兩版可同時 commit，git 歷史清楚
- Xcode 版 `DerivedData/` 預設在 `~/Library/Developer/Xcode/DerivedData/`（不污染 repo）；若改放專案內須加 `.gitignore`
- **退場**：Xcode 版若不滿意，刪整個 `approach-7-xcode/` 即可，Python 版零影響
- ⚠️ 兩版**不要同時執行**（會搶同一個全局熱鍵 + 同一支 session log DB）；測 Xcode 版前先結束 Python 版

---

## 10. 給新 session 的起手指引

1. 先讀本檔（planxcode060614.md）+ `AGENTS.md` + `approach-6-whisper-macos/INDEX.md`
2. 對照 approach-6 各模組原始碼（已是行為的 source of truth）
3. 依 §7 Phase 0 → 7 順序實作，**每個 Phase build 過 + 手動驗證再前進**
4. 拼音引擎（§4.7）先寫測試對拍 pypinyin，再接 VocabStore
5. 完成後更新 `AGENTS.md`（approach-7 轉現役候選）、根 README、`docs/agent-progress.md`
