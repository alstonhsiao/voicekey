# 啟動方式說明

## 從 Keyboard Maestro 啟動

### 方式一：Execute Shell Script（推薦，靜默背景執行）

在 Keyboard Maestro 加一個 **Execute Shell Script** action，內容填：

```bash
cd /Users/alstonmacminim4home/Documents/AntiGravity/voicekey/approach-6-whisper-macos

# 清除殘留 PID
PID_FILE="$HOME/Library/Application Support/WhisperVoice/WhisperVoice.pid"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    kill -0 "$OLD_PID" 2>/dev/null || rm -f "$PID_FILE"
fi

# 背景啟動
nohup .venv/bin/python main.py >> "$HOME/Library/Logs/WhisperVoice/app.log" 2>&1 &
```

**設定：**
- Execute with：`/bin/zsh`（或 `/bin/bash`）
- In background：打勾（讓 KM macro 不卡住等待）

Log 輸出位置：`~/Library/Logs/WhisperVoice/app.log`

---

### 方式二：Open File（會開 Terminal 視窗）

在 Keyboard Maestro 加一個 **Open a File, Folder or Application** action，選擇：

```
/Users/alstonmacminim4home/Documents/AntiGravity/voicekey/approach-6-whisper-macos/start-voice.command
```

會彈出一個 Terminal 視窗顯示即時 log，關閉視窗不影響程式繼續運行。

---

## 從終端機手動啟動

```bash
cd /Users/alstonmacminim4home/Documents/AntiGravity/voicekey/approach-6-whisper-macos
.venv/bin/python main.py
```

## 注意事項

- 首次啟動需在系統設定授權三項權限：**麥克風 / 輔助使用 / 輸入監控**
- 授權後需重新啟動程式才會生效
- 若已有一個實例在執行，重複啟動會自動退出（單例鎖保護）
