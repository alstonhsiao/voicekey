# GOTCHAS-xcode.md

> approach-7-xcode 實機除錯踩過的坑與**已確認解法**。下次遇到先看這裡。
> 記錄日期：2026-06-14（首次實機跑通 錄音→STT→LLM→詞彙→自動貼上 全管線）。

---

## 1. AVAudioEngine 錄音（macOS 26）

實機在 macOS 26 上連續踩三個雷，全在 `WhisperVoice/Audio/AudioRecorder.swift`：

### 1a. tap callback 永遠不觸發（錄到 0 samples → 「錄音時間太短」）
- **症狀**：`engine.start()` 成功、log 印出輸入格式，但 tap 的 `collect()` 從不被呼叫，`bufferSamples` 一直 0。
- **根因**：先呼叫 `engine.prepare()` 再 `installTap`，macOS 26 對「prepare 後才安裝」的 tap 不投遞 audio buffer。
- **解法**：**先 `installTap` 再 `engine.start()`**（不要顯式呼叫 `prepare()`，讓 `start()` 內部處理）。

### 1b. 第二次按熱鍵錄音直接 crash（NSException）
- **症狀**：第一次錄音 OK，第二次 `installTap` 丟 NSException（`AVAudioEngineImpl::InstallTapOnNode`）→ SIGABRT。
- **根因**：重用同一個已 `stop()` 的 `AVAudioEngine` 物件，macOS 26 對其再次 `installTap` 會丟例外（engine 內部狀態未完全重置）。
- **解法**：`engine` 宣告為 `var`，**每次 `start()` 都 `engine = AVAudioEngine()` 建新的**。

### 1c. 指定輸入裝置後 `engine.start()` 回 -10868（kAudioUnitErr_FormatNotSupported）
- **症狀**：用 `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` 換成 USB 麥克風後，start 失敗 `Code=-10868`，錯在 `AUGraphParser::InitializeActiveNodesInInputChain`。
- **根因**：改裝置後 `inputNode.outputFormat(forBus:0)` **不會更新**，仍是 engine 建立當下「系統預設裝置」的格式；`installTap(format: nil)` 會用這個過時格式，和新裝置真實硬體格式不符 → chain 初始化失敗。
- **解法**：tap 格式改用 **`inputNode.inputFormat(forBus: 0)`**（即時查 AUHAL，反映目前選定裝置的真實硬體格式），不要用 `nil` 也不要用 `outputFormat`。並加 `sampleRate > 0` guard。

> 三者最終正確順序：建新 engine → 設裝置 → 讀 `inputFormat(forBus:0)` → `installTap(format: 該格式)` → `engine.start()`。對齊 approach-6 Python 的「audio thread 只累積 buffer、轉檔在 stop() 做」設計。

---

## 2. 每次 rebuild 都掉「輔助使用」授權 → 用 self-signed 憑證

- **症狀**：清單裡 WhisperVoice 開關是開的（常顯示為**空白白紙圖示**），但程式 `AXIsProcessTrusted()` 回 false，文字只能進剪貼簿無法自動貼上。
- **根因**：**ad-hoc 簽章**（`codesign -s -`）每次 rebuild 產生新 cdhash，macOS TCC 對 ad-hoc app 用 path+cdhash 綁授權 → 重編就失效，舊記錄變殘骸。
- **解法**：改用**固定的 self-signed code-signing 憑證**，TCC 改綁 designated requirement（憑證 identity），rebuild 換 cdhash 也不掉授權。
  1. 跑一次 `bash setup-signing-cert.sh`（建憑證、匯入 login keychain、設 partition list）。
  2. `project.yml`：`CODE_SIGN_IDENTITY: "WhisperVoice Self-Signed"`（已設好）。
  3. **換簽章 identity 後仍要重新授權一次**：移除舊的白紙殘骸 → 啟動新 app → 授權 → 重啟生效。之後 rebuild 永久有效。

### setup-signing-cert.sh 本身踩過的坑（已在腳本內修掉，供參）
- **`security import` 回 `MAC verification failed`**：①Homebrew OpenSSL 3.x 產的 p12 用新版 MAC，macOS 不認 → 改用 `/usr/bin/openssl`（LibreSSL）。②**空密碼**的 p12 也被拒 → 給一個非空臨時密碼（`-passout pass:xxx` + `import -P xxx`）。
- **codesign 回 `ambiguous, matches more than one`**：keychain 堆積多張同名憑證。`delete-certificate -c name` 在多張時會拒刪，**必須用 SHA-1 逐一刪**：`find-certificate -a -c NAME -Z` 抓 hash → `delete-certificate -Z <sha1>`。腳本開頭已自動做這件事。
- **`CERT_CN: unbound variable`（bash）**：`echo "...「$CERT_CN」..."` 變數後緊貼全形字元，在非 UTF-8 locale 下 bash 把多位元組 byte 併進變數名 → `set -u` 報錯。解法：變數用 `${CERT_CN}` 並避免緊貼全形標點。

---

## 3. self-signed + hardened runtime → 啟動即 crash「Library not loaded: WhisperVoice.debug.dylib」

- **症狀**：改用 self-signed 憑證後 `open` app 完全不啟動，crash report：`Library not loaded: @rpath/WhisperVoice.debug.dylib ... different Team IDs`，DYLD SIGABRT。
- **根因**：Xcode 16 Debug build 預設把程式拆成獨立的 `WhisperVoice.debug.dylib`。ad-hoc 時主程式與 dylib 都 ad-hoc，dyld 放行；換 self-signed 憑證（TeamID "not set"）**搭配 hardened runtime** 後，dyld 嚴格比對 Team ID → 拒載 dylib。
- **解法**（`project.yml`，自用、不 notarize）：
  - `ENABLE_HARDENED_RUNTIME: NO`
  - `ENABLE_DEBUG_DYLIB: NO`（消除 .debug.dylib 拆分，程式碼直接進主執行檔）
- 驗證：`MacOS/` 下只剩 `WhisperVoice`、`otool -L` 無 debug.dylib 依賴、`codesign -dvvv` 顯示 `flags=0x0(none)`。
- 註：日後若要 Developer ID + notarization 分發，需重新開 hardened runtime 並用正式憑證（Team ID 一致就不會有此問題）。

---

> 對應修正 commit 見 git log（2026-06-14 approach-7 實機除錯）。
