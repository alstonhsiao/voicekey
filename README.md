# 語音轉文字工具 (Voice Typing)

> **按熱鍵 → 錄音 → API 辨識 → 自動貼上文字到游標位置**

雙層架構：**Grok STT（第一層）→ Cerebras LLM 修正（第二層）**，解決繁簡混用、標點遺漏、人名術語辨識問題。

---

## 方案說明

| 方案 | 平台 | 狀態 | 說明 |
|---|---|---|---|
| **approach-6-whisper-macos** | macOS | ✅ **現役主力** | Grok STT + Cerebras LLM，rumps 選單列，macOS 26 相容 |
| **approach-3-python-exe** | Windows | 🗄️ 封存（有空再維護）| Python 打包 .exe，OpenAI Whisper，供同事雙擊使用 |

> **已刪除**（2026-06-12）：approach-1（Python+uv）、approach-2（AHK+MCI）、approach-4（Gemini Windows）、approach-5（Gemini macOS）。刪除原因：approach-2 有 Critical 安全問題；approach-4/5 依賴 gemini-1.5-flash（已退役，API 回 404）；approach-1 功能被 approach-3 取代。

---

## 目錄

- [approach-6：macOS 主力方案（現役）](#approach-6macos-主力方案現役)
- [approach-3：Windows 封存方案](#approach-3windows-封存方案)
- [測試 API Key](#測試-api-key)
- [設定說明](#設定說明)
- [技術細節](#技術細節)

---

## approach-6：macOS 主力方案（現役）

### 功能一覽

| 功能 | 說明 |
|---|---|
| 🎤 **rumps 選單列** | 右上角圖示顯示狀態（⏸ / 🔴 / 🔄 / ⚠️），點選可切換模式或結束 |
| 📝 **四種模式** | 直接轉錄 / 中翻英 / 專業模式 / 一般對話 |
| 🔀 **Ctrl+F1 切換錄音** | 按一下開始，再按一下停止辨識貼上 |
| ⚡ **Grok STT** | 平均 ~1.0s，延遲穩定 |
| 🧠 **Cerebras LLM 修正** | ~170ms，修正繁簡混用 / 字間空格 / 標點 / 術語人名 |
| 📋 **詞彙無上限** | `llm_prompt` 可放數百術語，只改 config.json 不動 code |
| 🔌 **Provider 切換** | config.json 一行切換 grok / openai / groq |
| 🖥️ **macOS 26 相容** | rumps 主執行緒；pynput 貼上由 GCD 主執行緒執行（修正 TSM 崩潰）|
| 📊 **Session log** | 每次辨識寫入 `~/.whisper_voice_log.db`（STT、LLM、貼上結果）|

### 安裝

**最快方式（自動安裝腳本）：**
```bash
cd approach-6-whisper-macos
bash install.sh
```
腳本會檢查 Python 版本、建立 venv、安裝套件、互動式設定 API Key，最後產生「啟動語音輸入.command」捷徑。

**手動安裝：** 見 [approach-6-whisper-macos/install_manual.md](approach-6-whisper-macos/install_manual.md)

### API Key 設定

編輯專案根目錄的 `env.local`：
```
# STT provider（擇一）
XAI_API_KEY=xai-你的Key       ← 推薦（Grok STT，最快）
OPENAI_API_KEY=sk-你的Key     ← 備用（OpenAI Whisper）
GROQ_API_KEY=gsk_你的Key      ← 備用（免費額度較多）

# LLM 修正層
CEREBRAS_API_KEY=csk-你的Key  ← 免費方案每天 1M tokens
```

> `env.local` 已列入 `.gitignore`，不會推送到 GitHub。請確認檔案權限為 `chmod 600 env.local`。

確認 `config.json` 的 `api.provider` 對應你填的 STT Key：
```json
"api": { "provider": "grok" }    ← 對應 XAI_API_KEY
"api": { "provider": "openai" }  ← 對應 OPENAI_API_KEY
"api": { "provider": "groq" }    ← 對應 GROQ_API_KEY
```

### 日常操作

| 動作 | 說明 |
|---|---|
| 按 **Ctrl+F1**（第一下）| 開始錄音（等 beep 聲才說話）|
| 按 **Ctrl+F1**（第二下）| 停止錄音 → 辨識 → 貼到游標位置 |
| 按 **F10** | 切換辨識模式（循環）|
| 點選單列 **🎤 圖示** | 展開模式選單，直接選目標模式 |
| 選單列 **❌ 結束程式** | 結束程式 |

### macOS 權限設定（首次）

程式啟動後，三項都要允許：

| 授權 | 用途 | 少了會怎樣 |
|---|---|---|
| 麥克風 | 錄音 | 無法錄音 |
| **輔助使用 (Accessibility)** | **osascript 發送 Cmd+V 貼上** | **辨識成功但文字不貼上** ⚠️ |
| 輸入監控 (Input Monitoring) | 偵測 Ctrl+F1 / F10 | 熱鍵無反應 |

> 授權後需**重新啟動程式**才會生效。
> 位置：系統設定 → 隱私權與安全性 → 輔助使用 / 輸入監控，確認 Terminal 已打勾。

### 辨識模式

| 模式 ID | 顯示名 | 行為 |
|---|---|---|
| `direct` | 📝 直接轉錄 | 繁體中文忠實輸出（`zh-TW`），含個人術語 |
| `zh2en` | 🌐 中翻英 | 說中文，輸出英文 |
| `pro` | 💼 專業模式 | 技術術語（API, Docker, n8n 等）保留英文 |
| `casual` | 💬 一般對話 | 口語化輸出，不加句點 |

### 新增術語 / 人名

只需編輯 `config.json`，不需改 code，重啟生效：
- `grok_keyterms`：STT 層詞彙 hint（≤10 個，每個 ≤50 字元）
- `llm_prompt`：LLM 層完整指令，可放數百術語

---

## approach-3：Windows 封存方案

> 🗄️ **封存狀態** — 目前可用，但有已知問題待修，有需要時再繼續維護。

### 已知問題（修之前不要直接發給同事）

- **build.bat** 的 `--add-data config.json` 會把設定（可能含 key）打包進 exe，需移除
- **requirements.txt** 未鎖版本（全 `>=`），打包結果不可重現
- 錄音暫存 WAV 使用固定路徑且用後不刪除

### 快速使用（原始碼方式）

```batch
cd approach-3-python-exe
pip install -r requirements.txt
python main.py
```

編輯 `config.json` 填入 `openai_api_key`（或在 `env.local` 設 `OPENAI_API_KEY`）。

### 打包成 .exe（在 Windows 上執行）

```batch
pip install pyinstaller
build.bat
```
產物在 `dist\WhisperVoiceTyping.exe`，連同 `config.json` 一起傳給同事。

> ⚠️ 打包前先確認 `config.json` 的 key 欄位為空（`YOUR_KEY_HERE`），避免金鑰打包進 exe。
> PyInstaller 只能在目標平台打包，macOS 上無法產生 Windows .exe。

---

## 測試 API Key

```bash
# OpenAI / xAI / Groq
python test_api_key.py

# Cerebras
python test_cerebras.py
```

---

## 設定說明

### API Key 優先順序

1. 系統環境變數（`OPENAI_API_KEY` 等，最優先）
2. `env.local` / `.env.local`
3. `config.json` 的 `api_key` 欄位

### approach-6 config.json 主要欄位

```jsonc
{
  "api": {
    "provider": "grok",           // grok | openai | groq
    "grok": { "api_key": "" },    // 或由 env.local 覆蓋
    "llm_correction": {
      "provider": "cerebras",
      "cerebras": { "model": "gpt-oss-120b", "max_tokens": 2048 }
    }
  },
  "hotkey": {
    "record_key": "F1",
    "record_modifier": "ctrl",    // ctrl | shift | "" (空=無修飾鍵)
    "mode_cycle_key": "F10"
  },
  "modes": [ ... ],               // 見 config.json 各 mode 設定
  "ui": { "hud_enabled": false }  // macOS 26 上保持 false
}
```

### 錄音規格（approach-6）

| 參數 | 值 |
|---|---|
| 取樣率 | 16000 Hz |
| 聲道 | 1（Mono）|
| 位元深度 | 16-bit PCM |
| 格式 | WAV（辨識後刪除）|

---

## 技術細節

### 資料流（approach-6）

```
Ctrl+F1（第一下）
  → pynput 偵測按鍵
  → 背景執行緒錄音（sounddevice，記憶體 buffer）
  → 等 buffer > 4000 samples → beep 提示

Ctrl+F1（第二下）
  → 抓取前景 App 名稱
  → 停止錄音 → 寫 NamedTemp WAV
  → Grok STT API（~1.0s）
  → regex 修正（fallback 兜底）
  → Cerebras LLM 修正（~170ms，可選）
  → OpenCC 繁化兜底（偵測到簡體才轉）
  → pyperclip 寫剪貼簿 + osascript Cmd+V 貼上
    fallback → pynput（GCD 主執行緒）
  → SQLite session log
```

### macOS 26 相容修法

| 問題 | 修法 |
|---|---|
| rumps / AppKit 必須主執行緒 | `build_menubar_app()` 回傳 app，`main()` 主執行緒呼叫 `.run()`；listener 改 `.start()` 非阻塞 |
| Tk 全系列 SIGABRT | `_probe_tkinter()` 子程序探測；`hud_enabled: false` |
| pynput TSM 執行緒斷言 SIGTRAP | `_run_on_main_thread()` 透過 `libdispatch.dispatch_async_f` 排程到 GCD 主執行緒 |

### 錯誤處理

| 狀況 | 處理 |
|---|---|
| API Key 未設定 | 啟動時 RuntimeError，印出明確提示後退出 |
| 錄音 < 0.5 秒 | 忽略，不呼叫 API |
| HTTP 401 | 提示「API Key 無效」|
| HTTP 429 | 提示「請求過於頻繁」|
| 網路逾時（>30s）| 提示「網路逾時」|
| Cerebras 失敗 | 降級：直接貼原始 STT 文字（不中斷）|
| osascript 貼上失敗 | fallback → pynput（GCD）→ 剪貼簿（手動 Cmd+V）|

### 費用參考

| Provider | 費用 |
|---|---|
| Grok STT（xAI）| 依官方定價（[console.x.ai](https://console.x.ai/)）|
| OpenAI Whisper | $0.006 USD / 分鐘 |
| Groq Whisper | 免費額度較多 |
| Cerebras LLM | 免費方案每天 1M tokens |

---

## 授權

本專案供學習與個人使用。各 API 使用需遵守對應服務條款（OpenAI / xAI / Cerebras / Groq）。
