# VoiceKey — 語音轉文字

> **按熱鍵 → 錄音 → API 辨識 → 自動貼上文字到游標位置**

三層架構：**Grok STT（第一層）→ Cerebras LLM 修正（第二層）→ 拼音詞彙精修（第三層）**，解決繁簡混用、標點遺漏、人名術語辨識問題。

> 文件索引：僅本檔（根目錄）使用 `README.md`；各子資料夾以 `INDEX.md` 為入口（見 [docs/INDEX.md](docs/INDEX.md)）。  
> Agent 開工先讀 [AGENTS.md](AGENTS.md)。

---

## 方案一覽

| 方案 | 平台 | 狀態 | 說明 |
|---|---|---|---|
| **VoiceKey**（`voicekey/`） | macOS | ✅ **主力** | 原生 Swift/AppKit。本機實機跑通全管線；34 單元測試。見 [voicekey/INDEX.md](voicekey/INDEX.md) |
| **approach-6-whisper-macos** | macOS | 🧊 **凍結退路** | Python + rumps。2026-07-11 起不再修改 |
| **approach-3-python-exe** | Windows | 🗄️ **封存** | .exe 打包方案，勿改除非明確需求 |

---

## 快速開始（VoiceKey，本機開發機）

### 需求

- 完整 Xcode（非僅 Command Line Tools）
- `xcodegen`：`brew install xcodegen`
- API keys：`XAI_API_KEY`（Grok STT）、`CEREBRAS_API_KEY`（LLM 修正）

### 首次：簽章憑證（每台開發機一次）

```bash
cd voicekey
bash setup-signing-cert.sh   # 建立 "VoiceKey Self-Signed"
```

固定 identity 後，rebuild **不會**每次掉「輔助使用」授權（ad-hoc 會掉）。詳見 [GOTCHAS-xcode.md](voicekey/GOTCHAS-xcode.md)。

### 建置 / 測試 / 安裝

```bash
cd voicekey
./test.sh       # 單元測試
./package.sh    # Release + self-signed → ~/Library/Developer/VoiceKey-DD/.../VoiceKey.app
# 拖進 /Applications，或 ditto 覆蓋
```

### API Key（本機）

```bash
mkdir -p "$HOME/Library/Application Support/VoiceKey"
# 編輯 env.local（chmod 600），至少：
# XAI_API_KEY=...
# CEREBRAS_API_KEY=...
```

Key 讀取順序：環境變數 → App Support `env.local` → Keychain → bundle `config.json`。  
**絕不**把 key 提交 git 或打包進 `.app`。

### 使用

| 操作 | 說明 |
|---|---|
| **Ctrl+F1** | 開始 / 停止錄音 → 辨識 → 貼上 |
| **Ctrl+F10** | 循環切換模式 |
| 選單列 🎤 | 模式、詞彙檔、關於、結束 |

首次需允許：**麥克風**、**輔助使用**（不需「輸入監控」）。

### 詞彙與本機覆蓋

| 路徑（皆在 `~/Library/Application Support/VoiceKey/`） | 用途 |
|---|---|
| `user_vocab.json` 等 | 三層詞彙；首次啟動由 bundle 種子；存檔即熱重載 |
| `config.local.json` | 本機 deep merge（例如 `recording.input_device`）|

---

## 跨機部署（其他 Mac，無需 Xcode）

1. 在開發機產出分發包：

```bash
cd voicekey
./package.sh && ./make-distribution.sh
# → voicekey/dist/VoiceKey-macOS-YYYYMMDD.zip 與 .dmg
```

2. 把 zip/dmg 拷到目標機（AirDrop / USB / 內網）。  
   二進位產物**預設不進 git**（體積與簽章為本機產物）；安裝說明在 repo：  
   [voicekey/dist/INSTALL-zh-TW.md](voicekey/dist/INSTALL-zh-TW.md)

3. 目標機：拖 `VoiceKey.app` → `/Applications` → **右鍵「開啟」**（未 notarize，Gatekeeper 提示屬正常）→ 設定各機 `env.local` 與權限。

也可請目標機上的 AI agent 依下方「跨機部署 prompt」執行（需你先提供 zip/dmg 路徑與 API keys）。

---

## 辨識模式

| ID | 顯示 | 行為 |
|---|---|---|
| `direct` | 直接轉錄 | 繁中忠實輸出 |
| `zh2en` | 中翻英 | 說中文，輸出英文 |
| `pro` | 專業模式 | 技術術語保留英文 |
| `casual` | 一般對話 | 口語化 |

---

## approach-6（凍結退路）

僅在 VoiceKey 不可用時使用。安裝見 [approach-6-whisper-macos/INDEX.md](approach-6-whisper-macos/INDEX.md) 與 `install.sh`。  
**勿與 VoiceKey 同時執行**（搶熱鍵與 log）。

---

## approach-3（Windows 封存）

見 [approach-3-python-exe/INDEX.md](approach-3-python-exe/INDEX.md)。打包前確認 config 內無真實 API key。

---

## 測試 API Key（開發用）

```bash
python scripts/test_api_key.py    # OpenAI / xAI / Groq
python scripts/test_cerebras.py   # Cerebras
```

---

## 技術摘要（VoiceKey）

```
Ctrl+F1
  → Carbon 熱鍵 → AVAudioEngine 錄音（16k mono PCM16）
  → Grok STT（keyterm hint）
  → Cerebras LLM 修正（失敗則用 raw STT）
  → 拼音詞彙 fuzzy（user_vocab.json）
  → NSPasteboard + CGEvent Cmd+V
  → SQLite session log（~/.voicekey_log.db）
```

| 項目 | 說明 |
|---|---|
| 簽章 | self-signed `VoiceKey Self-Signed`；未 notarize |
| DerivedData | `~/Library/Developer/VoiceKey-DD`（避開 iCloud 專案目錄） |
| Log | `~/Library/Logs/VoiceKey/app.log` |
| Bundle id | `com.alston.VoiceKey` |

---

## 開發者 / AI Agent

| 文件 | 用途 |
|---|---|
| [AGENTS.md](AGENTS.md) | Governance — 每個 session 先讀 |
| [docs/INDEX.md](docs/INDEX.md) | Agent 文件路由 |
| [docs/agent-progress.md](docs/agent-progress.md) | 近期進度 |
| [todo.md](todo.md) | 待辦 |
| [voicekey/INDEX.md](voicekey/INDEX.md) | VoiceKey 建置與安裝 |
| [voicekey/GOTCHAS-xcode.md](voicekey/GOTCHAS-xcode.md) | 實機踩坑 |

---

## 授權

本專案供學習與個人使用。各 API 使用需遵守對應服務條款（OpenAI / xAI / Cerebras / Groq）。
