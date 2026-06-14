# WhisperVoice — Xcode 原生版（approach-7）

> 現役 Python 方案（`approach-6-whisper-macos/`）的原生 Swift / AppKit 重寫版。
> 與 Python 版**並排存活**：不滿意刪掉整個 `approach-7-xcode/` 即可，Python 版零影響。
>
> 架構與分階段計畫見專案根目錄 `planxcode060614.md`；治理見 `AGENTS.md`。

## 這是什麼

選單列常駐 App（無 Dock 圖示），按熱鍵錄音 → Grok STT → Cerebras LLM 修正 →
三層詞彙精修 → 自動貼上到游標處。功能與 approach-6 對等。

### 與 Python 版的差異

| 面向 | Python（approach-6） | Xcode 原生版（approach-7） |
| --- | --- | --- |
| 全局熱鍵 | pynput（需「輸入監控」授權） | Carbon `RegisterEventHotKey`（**免輸入監控**） |
| 錄音 | sounddevice | AVAudioEngine + CoreAudio 裝置選擇 |
| 貼上 | osascript + pynput | NSPasteboard + CGEvent Cmd+V |
| 繁簡轉換 | OpenCC `s2twp` | **省略**（Cerebras prompt 已要求輸出繁體） |
| 拼音引擎 | pypinyin | `CFStringTransform`（已對拍 pypinyin） |
| 打包 | venv + pip | 單一 `.app`，拖進 `/Applications` 即可 |
| 閒置記憶體 | ~149MB | 預期 < 40MB |

三層詞彙、四模式、provider 抽象、session log、config 行為皆與 Python 版一致。

## 建置需求

- 完整 Xcode（非僅 Command Line Tools）；本專案以 Xcode 26 驗證
- `xcodegen`：`brew install xcodegen`

## 首次：建立簽章憑證（一次性，每台機器做一次）

```bash
cd approach-7-xcode
bash setup-signing-cert.sh   # 建 self-signed code-signing 憑證，匯入 login keychain
```

**為什麼必要**：若用 ad-hoc 簽章（`codesign -s -`），每次 rebuild 都會產生新 cdhash，
macOS「輔助使用」授權綁的是 path+cdhash → **每次重編都掉授權**，文字無法自動貼上。
改用固定的 self-signed 憑證後，TCC 改綁憑證 identity，rebuild 不再掉授權（只需授權一次）。
`project.yml` 已設 `CODE_SIGN_IDENTITY: "WhisperVoice Self-Signed"`。
踩過的坑與細節見 `GOTCHAS-xcode.md`。

> 換簽章 identity（含首次從 ad-hoc 切過來）後，仍需到「輔助使用」**重新授權一次**：
> 移除舊的白紙殘骸 → 啟動新 app → 允許 → 重啟生效。之後永久有效。

## 建置 / 測試 / 打包

```bash
cd approach-7-xcode

./build.sh            # Debug build（self-signed 簽章；xcodegen generate + xcodebuild）
./test.sh             # 跑單元測試（拼音對拍、三層詞彙、provider 組裝、Cerebras 降級）
./package.sh          # Release build + 簽章 + 驗證
```

> ⚠️ **DerivedData 必須在 iCloud 同步目錄（`~/Documents`）之外**，否則 build 產物
> `.app` 會被加上 `com.apple.FinderInfo`，導致 codesign 失敗。腳本預設用
> `~/Library/Developer/WhisperVoice-DD`（可用 `WHISPERVOICE_DD` 覆蓋）。

產出路徑：`~/Library/Developer/WhisperVoice-DD/Build/Products/<Debug|Release>/WhisperVoice.app`

## 安裝（自用同一台）

1. `./package.sh` 產生 Release `.app`，拖進 `/Applications`。
2. **API Key**：把含 `XAI_API_KEY` / `CEREBRAS_API_KEY` 的 `env.local` 放到
   `~/Library/Application Support/WhisperVoice/env.local`（`chmod 600`）。
   - Key 解析優先序：環境變數 → 上述 `env.local` → Keychain → `config.json`。
   - Key **絕不**進 git、絕不打包進 `.app`。
3. 首次啟動會跳出授權對話框，請逐一允許（見下表）。

首次啟動所需授權：

| 授權 | 用途 | 少了會怎樣 |
| --- | --- | --- |
| 麥克風 | 錄音 | 無法錄音 |
| 輔助使用（Accessibility） | CGEvent 合成 Cmd+V | 辨識成功但不會自動貼上（文字留在剪貼簿） |
| 輸入監控 | **不需要**（Carbon 熱鍵的好處） | — |

## 使用

- **Ctrl + F1**：開始 / 停止錄音（聽到提示音後開始說話）
- **Ctrl + F10**：循環切換四模式（直接轉錄 / 中翻英 / 專業 / 一般對話）
- 選單列圖示：模式打勾切換、三層詞彙開檔（VSCode / 預設 App / Finder）、結束程式
- 狀態列即時顯示：⏸ 待機 / 🔴 錄音中 / 🔄 辨識中 / ⚠️ 錯誤

熱鍵可在 `config.json` 的 `hotkey` 區塊調整。

## 設定與詞彙

- **`config.json`**：隨 `.app` 內建的預設值（modes / api / hotkey / vocab）。
- **`config.local.json`**（放 `~/Library/Application Support/WhisperVoice/`）：
  本機覆蓋，deep merge，不同步到其他機器（多台 Mac 用）。
- **三層詞彙**（首次啟動自動從 bundle 種子到 App Support，可直接編輯、存檔即熱重載）：
  - `layer1_keyterms.json`：Grok STT 額外關鍵詞
  - `layer2_corrections.json`：LLM 修正詞（names + corrections，動態注入 prompt）
  - `user_vocab.json`：拼音 fuzzy 替換（people/companies/projects/terms + overrides）
    - 例：「蕭純云」自動修成「蕭淳云」（無聲調全拼音 + 同字數比對）

## 分發到其他 Mac（ad-hoc）

本版走 **ad-hoc 簽章**（免 Apple 付費帳號）。在別台 Mac 首次開啟：

- 右鍵 →「開啟」→ 確認；或
- `xattr -dr com.apple.quarantine /Applications/WhisperVoice.app`

每台 Mac 需**各自**在「系統設定 → 隱私權與安全性」勾選 **麥克風** 與 **輔助使用**。
（Developer ID + notarization 可免上述步驟，但需付費帳號 → 日後選配。）

## 退場 / 並排存活

- Python 版（`approach-6-whisper-macos/`）完全不動，隨時可回去用。
- 兩版**不要同時執行**：會搶同一個全局熱鍵與同一支 session log
  （`~/.whisper_voice_log.db`）。
- 不滿意 Xcode 版：刪掉整個 `approach-7-xcode/` 即可，Python 版零影響。

## 已知待辦 / 踩坑

- 需真人操作或跨機驗證的項目 → `ISSUES-xcode.md`
- 實機除錯踩過的坑與**確認解法**（macOS 26 AVAudioEngine 錄音三雷、self-signed 簽章、debug dylib crash）→ `GOTCHAS-xcode.md`

