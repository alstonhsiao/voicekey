# voicekey — VoiceKey Index（原 approach-7 / WhisperVoice，2026-07-11 改名）

> 前代 Python 方案的原生 Swift / AppKit 重寫版，現為**主力方案**。
> 歷史施工藍圖見 `docs/archive/planxcode060614.md`；治理見 `AGENTS.md`。

## 本目錄文件

| 檔案 | 用途 |
|---|---|
| `INDEX.md`（本檔） | 建置、安裝、使用、設定 |
| `GOTCHAS-xcode.md` | 錄音/簽章/build 踩坑與確認解法 |
| `ISSUES-xcode.md` | 待真人/跨機驗證項 |
| `dist/INDEX.md` | 分發產物（zip/dmg/安裝說明） |
| `build.sh` / `test.sh` / `package.sh` | 建置、測試、打包腳本 |

## 這是什麼

選單列常駐 App（無 Dock 圖示），按熱鍵錄音 → Grok STT → Cerebras LLM 修正 →
三層詞彙精修 → 自動貼上到游標處。功能與前代 Python 版對等。

### 與前代 Python 版的差異

| 面向 | Python（前代） | Xcode 原生版（VoiceKey） |
| --- | --- | --- |
| 全局熱鍵 | pynput（需「輸入監控」授權） | Carbon `RegisterEventHotKey`（**免輸入監控**） |
| 錄音 | sounddevice | AVAudioEngine + CoreAudio 裝置選擇 |
| 貼上 | osascript + pynput | NSPasteboard + CGEvent Cmd+V |
| 繁簡轉換 | OpenCC `s2twp` | **省略**（Cerebras prompt 已要求輸出繁體） |
| 拼音引擎 | pypinyin | `CFStringTransform`（已對拍 pypinyin） |
| 打包 | venv + pip | 單一 `.app`，拖進 `/Applications` 即可 |
| 閒置記憶體 | ~149MB | 預期 < 40MB |

三層詞彙、四模式、provider 抽象、session log、config 行為皆與前代 Python 版一致。

## 建置需求

- 完整 Xcode（非僅 Command Line Tools）；本專案以 Xcode 26 驗證
- `xcodegen`：`brew install xcodegen`

## 首次：建立簽章憑證（一次性，每台機器做一次）

```bash
cd voicekey
bash setup-signing-cert.sh   # 建 self-signed code-signing 憑證，匯入 login keychain
```

**為什麼必要**：若用 ad-hoc 簽章（`codesign -s -`），每次 rebuild 都會產生新 cdhash，
macOS「輔助使用」授權綁的是 path+cdhash → **每次重編都掉授權**，文字無法自動貼上。
改用固定的 self-signed 憑證後，TCC 改綁憑證 identity，rebuild 不再掉授權（只需授權一次）。
`project.yml` 已設 `CODE_SIGN_IDENTITY: "VoiceKey Self-Signed"`。
踩過的坑與細節見 `GOTCHAS-xcode.md`。

> 換簽章 identity（含首次從 ad-hoc 切過來）後，仍需到「輔助使用」**重新授權一次**：
> 移除舊的白紙殘骸 → 啟動新 app → 允許 → 重啟生效。之後永久有效。

## 建置 / 測試 / 打包

```bash
cd voicekey

./build.sh            # Debug build（self-signed 簽章；xcodegen generate + xcodebuild）
./test.sh             # 跑單元測試（拼音對拍、三層詞彙、provider 組裝、Cerebras 降級）
./package.sh          # Release build + 簽章 + 驗證
```

> ⚠️ **DerivedData 必須在 iCloud 同步目錄（`~/Documents`）之外**，否則 build 產物
> `.app` 會被加上 `com.apple.FinderInfo`，導致 codesign 失敗。腳本預設用
> `~/Library/Developer/VoiceKey-DD`（可用 `VOICEKEY_DD` 覆蓋）。

產出路徑：`~/Library/Developer/VoiceKey-DD/Build/Products/<Debug|Release>/VoiceKey.app`

## 安裝（自用同一台）

1. `./package.sh` 產生 Release `.app`，拖進 `/Applications`。
2. **API Key**：把含 `XAI_API_KEY` / `CEREBRAS_API_KEY` 的 `env.local` 放到
   `~/Library/Application Support/VoiceKey/env.local`（`chmod 600`）。
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
- 選單列圖示：模式打勾切換、三層詞彙開檔（VSCode / 預設 App / Finder）、關於 VoiceKey（版本）、結束程式
- 狀態列即時顯示：⏸ 待機 / 🔴 錄音中 / 🔄 辨識中 / ⚠️ 錯誤
- **版本查詢**：選單列 →「📦 關於 VoiceKey (vX.Y.Z build N)」，點擊開標準 About 面板。
  版本號在 `project.yml` 的 `MARKETING_VERSION` 手動管理；build 號由 `build.sh` / `package.sh`
  自動取 `git rev-list --count HEAD`，每個 build 可對回 commit。

熱鍵可在 `config.json` 的 `hotkey` 區塊調整。

## 設定與詞彙

- **`config.json`**：隨 `.app` 內建的預設值（modes / api / hotkey / vocab）。
- **`config.local.json`**（放 `~/Library/Application Support/VoiceKey/`）：
  本機覆蓋，deep merge，不同步到其他機器（多台 Mac 用）。
- **三層詞彙**（首次啟動自動從 bundle 種子到 App Support，可直接編輯、存檔即熱重載）：
  - `layer1_keyterms.json`：Grok STT 額外關鍵詞
  - `layer2_corrections.json`：LLM 修正詞（names + corrections，動態注入 prompt）
  - `user_vocab.json`：拼音 fuzzy 替換（people/companies/projects/terms + overrides）
    - 例：「蕭純云」自動修成「蕭淳云」（無聲調全拼音 + 同字數比對）

## 分發到其他 Mac

```bash
./package.sh && ./make-distribution.sh
# 產物：dist/VoiceKey-macOS-YYYYMMDD.zip 與 .dmg
```

本版為 **self-signed**（本機 rebuild 不掉輔助使用授權），**未 notarize**（免付費帳號）。  
在別台 Mac 首次開啟：

- 右鍵 →「開啟」→ 確認；或
- `xattr -dr com.apple.quarantine /Applications/VoiceKey.app`

每台 Mac 需**各自**：

1. 麥克風 + 輔助使用授權  
2. `~/Library/Application Support/VoiceKey/env.local`（API keys，不同步）  
3. （選配）`config.local.json` 指定 `recording.input_device`  

詳見 `dist/INSTALL-zh-TW.md`。Developer ID + notarization → 日後選配。

## 歷史來源

VoiceKey 取代的前代 Python 實作已移除；保留的設計決策、踩坑、OpenCC 差異與 Git 恢復方式見
`docs/archive/approach-6-macos.md`。

## 已知待辦 / 踩坑

- 需真人操作或跨機驗證的項目 → `ISSUES-xcode.md`
- 實機除錯踩過的坑與**確認解法**（macOS 26 AVAudioEngine 錄音三雷、self-signed 簽章、debug dylib crash）→ `GOTCHAS-xcode.md`
