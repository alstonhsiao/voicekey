# ISSUES-xcode.md

> voicekey 一口氣執行期間記錄的待處理問題。
> 格式見 planxcode060614.md §7。全部 Phase 跑完後一次回報給使用者。

---

## [Phase 0] 選單列圖示需真人目視確認

- 類型：需真人操作
- 現況：`xcodebuild build` 成功產出 `VoiceKey.app`，`@main` + `NSStatusItem` 顯示 🎤、含「❌ 結束程式」。Headless 無法目視選單列圖示。
- 暫時處理：build 成功 + .app 產出即視為自動驗證通過。
- 待辦：使用者執行 `open ~/Library/Developer/VoiceKey-DD/Build/Products/Debug/VoiceKey.app`，確認選單列右上出現 🎤，點開有「❌ 結束程式」。

## [Phase 0] DerivedData 不可放在 iCloud 同步目錄（已自動解決，記錄供參）

- 類型：技術阻擋（已解決）
- 現況：專案位於 `~/Documents`（iCloud fileprovider 同步），DerivedData 預設放專案內時，build 產物 `.app` 被加上 `com.apple.FinderInfo` / `com.apple.fileprovider.fpfs#P`，codesign 報 "resource fork, Finder information, or similar detritus not allowed"。
- 暫時處理：固定 DerivedData 到 `~/Library/Developer/VoiceKey-DD`（非同步目錄），build/test 一律經 `build.sh` / `test.sh`。已解決，不需使用者處理。
- 待辦：無（提醒：勿改回專案內 DerivedData）。

## [Phase 2] 麥克風授權 + 實機錄音講話測試需真人

- 類型：需真人操作
- 現況：build 成功；Carbon 熱鍵註冊成功（免「輸入監控」授權）；CoreAudio 列舉到 `USB PnP Audio Device(EEPROM)` 並依候選清單自動選中。麥克風授權對話框為非同步，需真人按「允許」；實際按 Ctrl+F1 講話錄音也需真人。
- 暫時處理：錄音管線（AVAudioEngine→16k mono PCM16 WAV）已完整實作；headless 僅驗證到列舉與熱鍵註冊。
- 待辦：使用者首次啟動 app 時於對話框允許「麥克風」；按 Ctrl+F1 講一句、再按一次停止，確認 `~/Library/Logs/VoiceKey/app.log` 出現「💾 WAV 已存…」且該 WAV 為 16k mono。

## [Phase 3] STT+LLM 真實 API 已驗證；中文語音準確度待真人

- 類型：待驗證（plumbing 已自動驗證）
- 現況：用 `say` 生成英文語音 → 真實 Grok STT 回 "Hello, this is a whisper voice native build test."，真實 Cerebras 修正為 "...Whisper voice..."（大小寫修正生效）。multipart 上傳、JSON 解析、金鑰解析、Cerebras 降級全部通過單元測試 + 真實 API。
- 暫時處理：無，API 串接已證實可運作。
- 待辦：使用者用麥克風講「中文」一段（含蕭淳云、加模等），確認 log 的 raw STT 與 LLM 修正後文字符合預期（中文辨識準確度本來就需真人耳判）。

## [Phase 4] 自動貼上 + 狀態列即時顯示需真人目視；獨立 .app 需各自授權

- 類型：需真人操作
- 現況：Paste 管線（NSWorkspace 前景 App → NSPasteboard → CGEvent Cmd+V）已實作；狀態列 ⏸/🔴/🔄/⚠️ 已接 VoiceController。從終端機啟動時 `AXIsProcessTrusted()` 回 true（繼承終端機的輔助使用授權），故貼上路徑可運作。
- 暫時處理：headless 驗證到狀態列初始化與授權檢查不崩潰。
- 待辦：①真人按 Ctrl+F1 講話，確認文字「貼到游標處」、狀態列即時切換 🔴→🔄→⏸。②**重要**：雙擊啟動的獨立 `VoiceKey.app` 是自己的責任程序，需在「系統設定 → 隱私權與安全性 → 輔助使用 / 麥克風」**各自**勾選 VoiceKey（與從終端機繼承不同）。

## [Phase 6] 模式選單打勾切換需真人目視

- 類型：需真人操作
- 現況：SessionLogger 已驗證（`~/.whisper_voice_log.db`，18 欄含 vocab_out / llm_finish_reason，權限 600）；單例鎖已驗證（第二實例偵測到並退出）；選單列已建 4 個模式項（打勾 current）+ Ctrl+F10 cycle 接線。
- 暫時處理：headless 驗證 DB schema + 單例鎖；選單打勾與 cycle 為 GUI 互動。
- 待辦：真人點選單列切換模式、按 Ctrl+F10，確認打勾跟著移動、標題模式更新。

## [Phase 7] Gatekeeper 拒絕 ad-hoc（預期）；notarization 與跨機分發

- 類型：需真人操作 / 技術阻擋（預期內）
- 現況：`package.sh` 完成 Release build + ad-hoc 簽章；`codesign --verify --deep --strict` 通過；`flags=0x2(adhoc)`。`spctl -a` 回 **rejected**（ad-hoc 未經 notarization，Gatekeeper 本來就拒）。
- 暫時處理：自用 OK（本機已可執行）。跨機需右鍵→開啟 或 `xattr -dr com.apple.quarantine`。
- 待辦：①跨機分發到其他 Mac mini 時，各機首次右鍵→開啟、並各自勾選麥克風/輔助使用。②若要免上述步驟 → Developer ID + `notarytool` notarization（需 Apple Developer 付費帳號，目前無，**日後選配**，不在本輪範圍）。

---

> 以上項目在 Phase 0→7 一口氣實作期間記錄。build/測試均已自動驗證通過；上述為需真人操作或跨機驗證的項目。