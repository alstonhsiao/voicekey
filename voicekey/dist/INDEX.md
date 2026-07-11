# voicekey/dist — 分發產物

> 由 `../make-distribution.sh` 產生（預設吃 `package.sh` 的 Release 產物）。

| 檔案 | 用途 |
|---|---|
| `INSTALL-zh-TW.md` | 跨機安裝、授權、env.local、config.local.json |
| `env.local.example` | API key 範例（複製到 App Support 後改名 env.local） |
| `VoiceKey-macOS-YYYYMMDD.zip` | 壓縮包（App + 說明 + example） |
| `VoiceKey-macOS-YYYYMMDD.dmg` | 磁碟映像（含 /Applications 捷徑） |
| `_dmg/` | 建 dmg 用暫存（可刪，下次 package 會重建） |

## 產製流程

```bash
cd voicekey
./package.sh                 # Release + self-signed 簽章
./make-distribution.sh       # → dist/VoiceKey-macOS-<今日>.zip|.dmg
# 或指定 app 路徑：
# ./make-distribution.sh /path/to/VoiceKey.app
```

## 跨機注意

- 未 notarize：目標機首次需右鍵「開啟」或清 quarantine。
- 每台各自：`env.local`、麥克風/輔助使用授權；麥克風不同用 `config.local.json`。
- 舊名 **WhisperVoice** 分發包已淘汰；請只用 `VoiceKey-macOS-*`。
