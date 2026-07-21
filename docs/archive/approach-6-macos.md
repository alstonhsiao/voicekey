# 前代 macOS Python 方案（approach-6）

> 歸檔日期：2026-07-22。原始碼目錄與本機虛擬環境已移除；完整 source 仍保留在 Git 歷史。

## 定位與架構

這是 VoiceKey 之前的 macOS Python 語音輸入實作，完整管線為：錄音 → Grok / OpenAI / Groq STT → Cerebras LLM 修正 → 三層詞彙 → 自動貼上。技術組合為 `sounddevice`、`pynput`、`rumps`、OpenCC、pypinyin 與 Python HTTP client。

它曾是 macOS 的主要方案，後來被原生 Swift/AppKit 的 VoiceKey 取代。VoiceKey 保留主要行為與資料格式；預設 `config.json`、`layer1_keyterms.json`、`layer2_corrections.json`、`user_vocab.json` 已確認與 VoiceKey Resources 一致。

## 保留的設計決策

- Grok STT 沒有 `prompt` 欄位，詞彙提示必須使用 `keyterm`；繁簡、標點、空格與術語修正交給 Cerebras。
- 三層詞彙：Layer 1 提供 STT keyterms、Layer 2 注入 LLM 修正提示、Layer 3 使用無聲調拼音與同字數 fuzzy 比對。
- 詞彙檔以 mtime 熱重載；後處理或 LLM 失敗時降級回原文字串，不讓程式崩潰。
- OpenCC `s2twp` 是前代版本的確定性繁簡保底；VoiceKey 目前刻意省略，改由 Cerebras prompt 處理。
- `~/.whisper_voice_log.db` 記錄 session，權限收斂為 `600`；VoiceKey 已沿用舊資料遷移邏輯。

## 重要踩坑與解法

- 自動貼上需要 Accessibility；Input Monitoring 是另一套權限。前代以 osascript 為主、pynput 為 fallback。
- macOS 26 要求 rumps UI 在主執行緒；Tk HUD 會觸發相容性崩潰，因此 HUD 預設關閉。
- macOS 26 的 TSM API 不可從背景執行緒呼叫；pynput 貼上路徑必須派送到 GCD 主執行緒。
- regex 只作 fallback，不負責移除字間空格；這類語意修正交給 LLM。
- SQLite session log 建立後必須 `chmod 600`，避免口述內容被同機其他使用者讀取。

## 與 VoiceKey 的關係

VoiceKey 已以原生 Swift/AppKit 重寫主要模組：Carbon 熱鍵、AVAudioEngine、NSPasteboard + CGEvent、Swift pinyin、三層詞彙、Cerebras fallback、單例鎖與 session log。VoiceKey 的單元測試已涵蓋前代 `test_vocab.py` 的 fuzzy、override、keyterm 與熱重載行為。

目前沒有保留可直接執行的 Python 回退版本；這是有意識的精簡取捨。若日後必須恢復，可從 Git 歷史取回，例如：

```bash
git show 409a3d7:approach-6-whisper-macos/main.py
git restore --source=409a3d7 -- approach-6-whisper-macos
```

相關歷史提交包括 `4d1f6ba`（初始方案）、`8572b67`（四模式與 Grok）、`8f17ea5`（Cerebras）、`346cdfb`（三層詞彙）、`65f4641`（數字格式規則）。文件只保留設計與行為摘要，不保存 API key、`.venv` 或本機環境資料。
