# Agent Gotchas

Known bugs, platform quirks, API limits, and their fixes for approach-6.
Read this when debugging a runtime failure, or before touching paste / audio / provider / HUD code.

---

## macOS 自動貼上失效：Accessibility ≠ Input Monitoring
- **症狀**：辨識成功、文字在剪貼簿，但不會自動貼到游標位置；osascript 印出 `error 1002`
- **根因**：macOS 有兩個獨立權限——Input Monitoring（偵測按鍵）和 Accessibility（模擬按鍵送 Cmd+V）。兩者都要開。
- **解法**：系統設定 → 隱私權與安全性 → **輔助使用** → Terminal ✓ → 重啟程式
- **程式碼**：`_voice_paste.py` `paste_text()` — osascript 為主，pynput 為 fallback

---

## macOS 26 啟動崩潰：rumps 必須在主執行緒
- **症狀**：`NSWindow should only be instantiated on the main thread!`
- **解法**：`build_menubar_app()` 回傳 app 物件，`main()` 在主執行緒呼叫 `rumps_app.run()`；pynput 改 `listener.start()` 非阻塞
- **程式碼**：`main.py` `main()` 尾端

---

## macOS 26 HUD 崩潰：Tk 全系列不相容
- **症狀**：`[NSApplication macOSVersion]: unrecognized selector` → SIGABRT
- **解法**：`config.json` 設 `"hud_enabled": false`；`_probe_tkinter()` 以子程序安全偵測
- **程式碼**：`_voice_hud.py` `_probe_tkinter()`

---

## Grok STT 沒有 prompt 欄位：繁簡問題根因
- **症狀**：辨識結果偶爾出現簡體中文，即使 config prompt 寫了「請使用繁體中文」
- **根因**：Grok STT API 只接受 `language` 和 `keyterm`，**沒有 `prompt` 欄位**。keyterm 是詞彙 hint，對字型無約束力。
- **解法**：Cerebras LLM 第二層負責繁簡轉換、字間空格、標點、術語修正。
  config.json 各 mode 有 `grok_keyterms`（≤10）與 `llm_prompt`。
- **API Key**：`CEREBRAS_API_KEY` 在 `env.local`，免費方案每天 1M tokens。

---

## macOS 26 TSM 執行緒斷言：pynput 從背景執行緒崩潰
- **症狀**：辨識完成後程式 SIGTRAP；crash log 顯示 `_dispatch_assert_queue_fail` → `TSMGetInputSourceProperty` → Thread-23
- **根因**：macOS 26 HIToolbox 新增 GCD 執行緒斷言——`TSMGetInputSourceProperty` 只能在主執行緒呼叫。`pynput.keyboard.Controller.press()` 內部呼叫此 API；若從背景執行緒觸發，直接 SIGTRAP 崩潰。
- **觸發條件**：Terminal 沒有 Accessibility 授權 → osascript 方案 A 失敗 → fallback 到 pynput → 崩潰
- **解法**：`_run_on_main_thread(fn)` helper 以 `libdispatch.dispatch_async_f` 把 pynput 排程到 GCD 主執行緒。`dispatch_get_main_queue` 在 macOS 26 已是 macro，改直接取 `_dispatch_main_q` symbol 位址。
- **程式碼**：`_voice_paste.py` → `_gcd_init()` / `_run_on_main_thread()` / `paste_text()` 的 pynput 路徑
- **根本預防**：授予 Terminal Accessibility 權限，讓 osascript 路徑正常運作，無須 pynput fallback

---

## Cerebras LLM fallback 原則
- **症狀**：Cerebras API 失敗時程式不應崩潰
- **解法**：`CerebrasProvider.correct()` 的 except 直接 return 原始 STT 文字（降級但不中斷）
- **程式碼**：`_voice_providers.py` `CerebrasProvider.correct()`

---

## regex 不做主要修正
- **決策**：regex 層（`apply_corrections`）僅保留作 fallback 兜底，不用於移除字間空格。
- **原因**：regex 無法區分字元空格與句子邊界空格，會造成「耶用」此類誤合。全部交由 LLM 處理。

---

## SQLite session log 權限
- **風險**：`~/.whisper_voice_log.db` 記錄所有口述文字，預設建檔權限 644（同機他人可讀）
- **現狀**：已修（2026-06-12）— `SessionLogger.__init__` 加入 `os.chmod(DB_PATH, 0o600)`
- **程式碼**：`_voice_session.py` `SessionLogger.__init__()`
