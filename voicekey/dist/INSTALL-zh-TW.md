# VoiceKey 安裝說明（macOS）

這份安裝包給「使用者端」安裝用，**不需要 Xcode**。  
適用：本機自用，或複製到其他 Mac mini 跨機部署。

## 內容物

- `VoiceKey.app`（bundle id：`com.alston.VoiceKey`）
- `INSTALL-zh-TW.md`（本文件）
- `env.local.example`

## 安裝步驟（每台 Mac 各做一次）

1. 把 `VoiceKey.app` 拖到 `/Applications`
2. 建立設定目錄（若不存在）：

```bash
mkdir -p "$HOME/Library/Application Support/VoiceKey"
```

3. 把 `env.local.example` 複製成 `env.local` 並填入 API keys：

```bash
cp env.local.example "$HOME/Library/Application Support/VoiceKey/env.local"
chmod 600 "$HOME/Library/Application Support/VoiceKey/env.local"
# 用你習慣的編輯器填入 XAI_API_KEY / CEREBRAS_API_KEY
```

4. **（選配，多機麥克風不同時）** 建立本機覆蓋檔：

```bash
# 範例：指定輸入裝置名稱（需與系統「聲音」裡顯示的名稱相符）
cat > "$HOME/Library/Application Support/VoiceKey/config.local.json" <<'EOF'
{
  "recording": {
    "input_device": "USB Audio Device"
  }
}
EOF
```

`config.local.json` 為 deep merge，**不要同步到其他機器**（每台各自寫）。

5. 第一次開啟時若 macOS 阻擋：
   - Finder 對 App **右鍵 →「開啟」→ 確認**；或
   - 終端機：

```bash
xattr -dr com.apple.quarantine /Applications/VoiceKey.app
open /Applications/VoiceKey.app
```

6. 依提示允許權限：
   - **麥克風**（錄音）
   - **輔助使用 / Accessibility**（自動 Cmd+V 貼上）

> 不需要「輸入監控」授權（熱鍵用 Carbon）。

## env.local 範例

至少需要：

```dotenv
XAI_API_KEY=xai-xxxx
CEREBRAS_API_KEY=csk-xxxx
```

也可改用其他 STT provider：

```dotenv
OPENAI_API_KEY=sk-xxxx
GROQ_API_KEY=gsk_xxxx
```

App 讀取順序：

1. 系統環境變數  
2. `~/Library/Application Support/VoiceKey/env.local`  
3. Keychain  
4. App 內建 `config.json`  

**API keys 絕不同步、不進 git、不打包進 .app。** 每台 Mac 各自一份。

## 使用方式

| 操作 | 說明 |
|------|------|
| `Ctrl + F1` | 開始 / 停止錄音 |
| `Ctrl + F10` | 循環切換模式（直接 / 中翻英 / 專業 / 一般） |
| 選單列 🎤 | 模式打勾、管理三層詞彙、關於、結束程式 |

狀態：⏸ 待機 → 🔴 錄音中 → 🔄 辨識中 → ⏸（貼上後）

## 簽章與 Gatekeeper

- 本安裝包為 **self-signed 或 ad-hoc 簽章**，**未經 Apple notarization**。
- 其他 Mac 第一次開啟出現 Gatekeeper 提示是**正常**的；用右鍵「開啟」即可。
- 若要在目標機本機重編並避免每次 rebuild 掉「輔助使用」授權，可在該機執行專案內 `setup-signing-cert.sh` 後再 `package.sh`（需 Xcode；日常使用者不必做）。

## 若無法開啟

```bash
xattr -dr com.apple.quarantine /Applications/VoiceKey.app
open /Applications/VoiceKey.app
```

## 若辨識成功但沒有自動貼上

通常是少了「輔助使用」授權。

1. 系統設定 → 隱私權與安全性 → 輔助使用  
2. 確認 **VoiceKey** 已勾選（路徑應為 `/Applications/VoiceKey.app`）  
3. 必要時移除舊項 → 重開 App → 再允許一次  

未授權時，文字仍會留在剪貼簿，可手動 Cmd+V。

## 舊版 WhisperVoice 使用者

若本機曾安裝舊名 **WhisperVoice**（`com.alston.WhisperVoice`）：

- 新版首次啟動會自動遷移 App Support 詞彙檔、keychain、session DB（不覆蓋已存在的新檔）。
- 可刪除 `/Applications/WhisperVoice.app`，並在「麥克風 / 輔助使用」列表移除舊項目，避免混淆。
- 請改授權 **VoiceKey**（bundle id 變更後 TCC 需重新勾一次，屬預期）。

## 除錯

Log：`~/Library/Logs/VoiceKey/app.log`  
Session DB：`~/.voicekey_log.db`（權限 600）

確認錄音裝置、STT/LLM 延遲、貼上是否成功，都可先看 app.log。
