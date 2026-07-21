# TODO — voicekey 專案

> 主力：**VoiceKey**（`voicekey/`）。
> 詳細真人/跨機項見 `voicekey/ISSUES-xcode.md`；踩坑見 `voicekey/GOTCHAS-xcode.md`。

---

## 高優先（改名後一次性收尾）

- [x] **安裝完整 Xcode**（本機 Xcode 26.6，`xcode-select` 已指向 Xcode.app）

- [x] **VoiceKey 簽章憑證 + 本機安裝**（2026-07-12 本機完成）
  - [x] `VoiceKey Self-Signed` 有效 identity（codesign Authority 已驗證）
  - [x] `xcodegen` 2.45.4
  - [x] Release 建置 → `/Applications/VoiceKey.app`（bundle `com.alston.VoiceKey` v0.1.0）
  - [x] App Support：`env.local` + 三層詞彙種子；XAI / CEREBRAS key 就緒
  - [x] 麥克風 + 輔助使用 + 熱鍵
  - [ ] （選配）`config.local.json` 指定麥克風（目前系統預設可用）

- [x] **端到端真人煙測**（2026-07-12 log 驗證）
  - [x] Ctrl+F1 → 錄音 → Grok STT → Cerebras LLM → CGEvent 貼上（ok=true）
  - [x] 簡體 STT `测试…` → LLM 修成 `測試測試123看看是不是很正常。`（STT 925ms / LLM 487ms）
  - [x] Ctrl+F10 / 選單切模式（2026-07-12 部署後真人驗證 #2）

---

## 部署後真人驗證（本機，2026-07-12 起）

> 路徑 A（`VoiceKey-macOS-20260712.dmg`）已裝至 `/Applications`；基礎煙測 + 輔助使用已通過。  
> 有空再逐項勾；log：`~/Library/Logs/VoiceKey/app.log`。

- [x] **#1 多 App 貼上** — TextEdit 以外（Safari / Cursor 等）確認 CGEvent 貼上正常
- [x] **#2 模式切換** — 選單列 🎤 四模式打勾 + `Ctrl+F10` 循環，標題更新正確
- [ ] **#3 中文 + 專有名詞** — 講含人名、公司名、專案名的句子；對照 log raw STT → LLM
- [ ] **#4 簡體輸入修正** — 故意講簡體或混雜用語，確認 Cerebras 轉繁體符合習慣
- [ ] **#5 冷啟動** — 選單列結束程式 → 雙擊 `/Applications/VoiceKey.app` 再煙測；權限不應掉
- [ ] **#6 單例鎖** — 再 `open /Applications/VoiceKey.app`，應只留一個實例
- [ ] **#7 選單列 UI** — 🎤 常駐、狀態 🔴→🔄→⏸ 即時、詞彙管理選單可開
- [ ] **（選配）長錄音** — 30s+ 延遲與穩定性
- [ ] **（選配）API 降級** — 暫時錯 key，確認不崩潰、降級回 raw STT
- [ ] **（選配）重開機後** — 確認是否要手動啟動或加登入項目

---

## 中優先

- [ ] **跨機部署到其他 Mac mini**（本機路徑 A 已完成；其他 Mac 待到機實裝）
  - 分發：`voicekey/dist/VoiceKey-macOS-20260712.zip` / `.dmg`
  - 步驟見 `voicekey/dist/INSTALL-zh-TW.md`
  - 各機：右鍵開啟（未 notarize）；各自麥克風/輔助使用
  - 各機 `config.local.json` 指定不同 `input_device`（麥克風名稱）
  - 各機 `env.local`（API keys，不同步）

- [x] **分發產物改名對齊 VoiceKey**（2026-07-12）
  - INSTALL / make-distribution / dist INDEX 全數 VoiceKey + `com.alston.VoiceKey`
  - 舊 `WhisperVoice-macOS-20260615.*` 已清；新產物 `VoiceKey-macOS-20260712.{zip,dmg}`
  - `make-distribution.sh` 預設路徑對齊 `package.sh`（`VoiceKey-DD`）

- [ ] **Grok STT 繁中 keyterm 實機累積**
  - 單元/TTS 已驗證；真人錄音再累積人名、公司名準確率
  - 必要時調 `vocab.stt_keyterm_limit` 或 LLM prompt

---

## 低優先 / 選配

- [ ] **Apple Developer + notarization**
  - 跨機免右鍵開啟、免清 quarantine；需付費帳號，非自用必要

- [ ] **OpenCC 保底（VoiceKey）**
  - 目前省略；Cerebras prompt 要求繁體。若實機仍偶發簡體再加（Swift 可嵌 C 庫或呼叫外部）

- [ ] **Groq Whisper 繁中品質/語速比較**
  - 已知約 0.5s；品質待對拍 Grok

- [ ] **系統音訊 / loopback 轉錄**
  - 目前只錄麥克風；YouTube 等需 BlackHole 類虛擬裝置 + 裝置選擇 UI

---

## 已完成（摘要）

- [x] VoiceKey Phase 0→7（Swift 原生版）+ 34 單元測試
- [x] 實機驗證：錄音→Grok STT→Cerebras→拼音詞彙→自動貼上
- [x] STT keyterm 動態合併 + 熱重載修正（user vocab 優先）
- [x] 台灣口語數字 → 半形阿拉伯數字（LLM prompt）
- [x] 改名 WhisperVoice → VoiceKey（目錄、bundle id、App Support 遷移）
- [x] 分發 zip/dmg 腳本 + 產物對齊 VoiceKey 名稱
- [x] 文件：`docs/archive/` 歸檔計畫；子目錄 `INDEX.md` 慣例
