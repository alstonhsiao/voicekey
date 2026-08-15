# VoiceKey Settings Window 實作計畫

> **狀態**：`IMPLEMENTED`（2026-08-15 Phase 0–5 已實作、測試並部署到 `/Applications`）
> **本次鎖定決策**：第一次啟動使用「專業模式」；之後預設記住最後使用模式。
> **前置條件**：start/stop 死結修復已完成；正式 App Icon 已完成；目前基線為 34 tests green。
> **預估規模**：約 1,000–1,300 行 Swift；12 個新檔案，加上既有程式、設定、測試與文件修改。
> **施工原則**：分階段完成與驗證；不可在設定變更後留下半套 runtime；API secrets 不得寫入 JSON/log/git。

---

## 1. 目標

在選單列加入標準「設定…」入口（`⌘,`），開啟原生 AppKit `NSWindow`，讓使用者不需直接編輯 JSON 即可管理常用設定。

### 必須完成

1. 首次啟動預設「專業模式」（`pro`）。
2. 預設記住最後使用模式；重啟後回到最後模式。
3. Settings 可切換「記住上次模式」；關閉時改用指定的固定預設模式。
4. Settings 分成 General / Hotkeys / Recording / API Keys / LLM 五個 tab。
5. 一般設定只寫 `~/Library/Application Support/VoiceKey/config.local.json`，不修改 bundle 的 `config.json`。
6. API keys 只寫 Keychain；登入項目使用 `SMAppService`；最後模式使用 `UserDefaults`。
7. 可即時套用的設定不需重啟 App；需要重建元件時必須在 idle 狀態做完整、可回復的 runtime swap。
8. Settings 寫入失敗、config 驗證失敗、熱鍵衝突或元件重建失敗時，舊設定與舊 runtime 必須繼續可用。

### 明確不做

- 編輯模式 prompt / keyterms / regex rules。
- 內建詞彙內容編輯器（維持外部編輯器入口）。
- HUD 設定（目前 HUD 未實作）。
- API 測試連線（v1 不做）。
- 字母鍵全域熱鍵（v1 僅 F1–F20）。
- 多語系 UI（v1 全繁體中文）。
- Developer ID / notarization。

---

## 2. 已確認的現有架構約束

| 約束 | 正確處理方式 |
|---|---|
| `AppConfig` 與子設定多為 struct/value type | Settings 不可持有「可變參考」假設；用 snapshot + `SettingsApplying` protocol 交給 `AppDelegate` 統一套用 |
| `ConfigLoader.load()` 只讀 `config.local.json` | 新增原子寫入、候選驗證與 rollback |
| `VoiceController` 持有 `config/transcribe/llm/vocab/recorder` 的舊副本 | 修改 recording、vocab、API、LLM、keyterm limit 後重建完整 runtime；不可只改 `AppDelegate.config` |
| `AudioRecorder` 在 init 時固定 `deviceSpec/sampleRate/targetFormat` | 輸入裝置與取樣率變更都必須重建 `AudioRecorder`，最簡單是重建 `VoiceController` |
| STT provider 在建立時持有 API config | API key 變更後重建 provider + `VoiceController` |
| `ModeManager.current` 與 `default_mode_id` 是不同概念 | Settings 顯示 persisted default；目前模式仍由選單切換，不能用 current 冒充 default |
| `HotkeyManager` 目前只在 deinit unregister | 新增可回復的 reconfigure；新熱鍵失敗時恢復舊熱鍵 |
| Carbon F1–F20 keyCode 並非連續值 | 使用 `KeyCodes` 明確 mapping 與 reverse lookup，不做範圍判斷 |
| App 是 `LSUIElement` | 顯示 Settings 前呼叫 `NSApp.activate(ignoringOtherApps: true)` |
| App 可能正在錄音／辨識 | runtime 設定套用前檢查 `VoiceController.isBusy`；忙碌時拒絕並提示先完成錄音 |
| API key 優先序為 process env → env.local → Keychain → config | UI 顯示 active source；process env/env.local 存在時明確提示 Keychain 變更目前不會生效 |
| 專案 `sources: - path: VoiceKey` | 新增 Swift 檔與 `.xcassets` 一樣會由 xcodegen 自動納入，不需逐檔改 `project.yml` |

### 不採用原稿的做法

- 不把多個 `let` 全面改成 `var` 後原地修改；這仍會讓既有物件持有 stale copies。
- 不讓 Settings controller 直接持有 `AppConfig` 並期待修改會回傳 AppDelegate。
- 不宣稱 input device、API key、keyterm limit 只改一個 property 就會即時生效。
- 不在沒有 rollback 的情況下先 unregister 全部熱鍵。

---

## 3. 啟動模式與記憶規則（已鎖定）

### 儲存

- bundle `config.json`: `default_mode_id = "pro"`（全新安裝／無偏好時的 fallback）。
- `config.local.json`: 使用者在 Settings 選擇的固定預設 `default_mode_id`。
- `UserDefaults`:
  - `rememberLastMode`：Bool，未設定時預設 `true`。
  - `lastModeId`：最後有效模式 id。

### 啟動選擇順序

1. 載入合併後的 `AppConfig`。
2. 若 `rememberLastMode == true`，且 `lastModeId` 仍存在於 `config.modes`，以它啟動。
3. 否則使用合併後的 `defaultModeId`。
4. 若 default id 無效，安全 fallback 到 modes 第一項並記 warning。

### 執行期間

- `ModeManager` 每次成功切換模式後，若 `rememberLastMode == true`，寫入 `lastModeId`。
- 開啟「記住上次模式」時，立即把目前模式存為 `lastModeId`。
- 關閉「記住上次模式」不刪 last id，但下次啟動忽略它；未來重新開啟仍可由當下模式覆寫。
- 修改「固定預設模式」只影響未使用記憶模式時的下次啟動，不強制切換目前模式。

### General UI

1. Checkbox：`記住上次使用模式`（預設開）。
2. Pop-up：`固定預設模式`，初始值必須取 `AppConfig.defaultModeId`，不是 `ModeManager.current.id`。
3. 記住模式開啟時，pop-up 可保持可用並加說明：「找不到上次模式時使用此值」。

---

## 4. 建議檔案結構

```text
voicekey/VoiceKey/
├── Settings/
│   ├── SettingsWindowController.swift
│   ├── SettingsTabViewController.swift
│   ├── SettingsModels.swift
│   ├── GeneralTabViewController.swift
│   ├── HotkeyTabViewController.swift
│   ├── RecordingTabViewController.swift
│   ├── APIKeysTabViewController.swift
│   ├── LLMTabViewController.swift
│   └── HotkeyRecorderField.swift
└── Core/
    ├── ConfigLocalWriter.swift
    ├── LoginItem.swift
    └── ModePreferenceStore.swift
```

### 既有檔案修改

| 檔案 | 修改內容 |
|---|---|
| `Resources/config.json` | `default_mode_id` 改為 `pro` |
| `AppDelegate.swift` | Settings window lifecycle、`SettingsApplying`、候選 runtime 建立與原子 swap |
| `MenuBarController.swift` | 增加「設定…」`⌘,`；以 closure 呼叫，避免 controller 直接耦合 `NSApp.delegate` |
| `VoiceController.swift` | 提供 thread-safe `isBusy/currentState`；讓 AppDelegate 能拒絕忙碌中重建 |
| `HotkeyManager.swift` | 保存 registration specs、`unregisterAll()`、失敗 rollback/reconfigure |
| `KeyCodes.swift` | F1–F20 正反向 mapping 與 validation |
| `Config.swift` | 提供候選 local override 的 load/validate 入口；避免全面改 mutable |
| `Secrets.swift` | key source 查詢、Keychain delete/replace、禁止輸出 key 值 |
| `VoiceKeyTests/` | writer、mode preference、runtime apply、hotkey rollback 相關測試 |
| `voicekey/INDEX.md` / `docs/agent-progress.md` / `todo.md` | 使用方式、完成狀態與人工驗證 |

> `AGENTS.md` 維持治理精簡；除非 Settings 形成需要獨立路由的大型 spoke，否則不加 Quick Map 項目。

---

## 5. Settings 視窗架構

### SettingsApplying protocol

Settings UI 不持有可變 `AppConfig`。新增 protocol（可放 `SettingsModels.swift`）：

```swift
protocol SettingsApplying: AnyObject {
    func settingsSnapshot() -> SettingsSnapshot
    func apply(_ change: SettingsChange) throws
}
```

- `AppDelegate` 實作 protocol，持有 runtime 的唯一真實狀態。
- 各 tab 只接收 snapshot 顯示，送出 typed change。
- 每次 window 顯示或 tab 成為 active 時刷新 snapshot，避免 UI 顯示舊資料。
- 錯誤由 tab 捕捉並用 `NSAlert` 顯示，不在 log 中寫秘密。

### SettingsWindowController

- `NSWindowController` + `NSTabViewController`，五個 `.topTabs`。
- title：`VoiceKey 設定`。
- 初始寬約 520pt；允許必要的垂直 resize，避免 API/env 警告文字被截斷。
- window close 後保留 controller，下次重用。
- `showWindow` 前 `NSApp.activate(ignoringOtherApps: true)`。
- 不建立第二份 runtime/config store。

### MenuBar 入口

- 在 About 前增加分隔線與「設定…」。
- key equivalent `,`，modifier `.command`，顯示標準 `⌘,`。
- `MenuBarController` init 接收 `onOpenSettings: () -> Void`，由 AppDelegate 傳入；不要在 MenuBar 內強轉 AppDelegate。

---

## 6. 五個 tab

### 6.1 General

1. `記住上次使用模式` checkbox → `ModePreferenceStore.rememberLastMode`。
2. `固定預設模式` pop-up → `config.local.json/default_mode_id`。
3. `登入時自動啟動` checkbox → `SMAppService.mainApp`。
4. `詞彙修正` checkbox → `vocab.enabled`；套用時重建 runtime。
5. `STT 關鍵詞上限` stepper，範圍採 Grok 現行程式限制 0–10；若未來 provider 放寬再調整。原稿的 0–50 與 `GrokTranscriber.prefix(10)` 不一致。
6. 權限區：顯示麥克風／輔助使用狀態；提供「打開系統設定」按鈕，不嘗試自行授權。
7. 詞彙管理入口沿用現有三層檔案開啟動作，可提供按鈕但不內嵌編輯器。

### 6.2 Hotkeys

1. 錄音熱鍵與切模式熱鍵。
2. 只接受修飾鍵 + F1–F20；透過 `KeyCodes` 明確 mapping/reverse mapping。
3. 不接受兩個功能使用相同組合。
4. 用「套用」按鈕一次提交。
5. 套用交易：保存舊 specs → unregister → 註冊兩個新組合；任何一個失敗就 unregister partial 並恢復兩個舊組合。
6. 只有成功後才寫入 `config.local.json`；若採先寫策略，失敗必須 restore snapshot。
7. UI 顯示衝突／註冊失敗，不可留下無熱鍵狀態。

### 6.3 Recording

1. 輸入裝置 pop-up：系統預設 + `CoreAudioDevices.allInputDevices()`。
2. 「重新掃描」按鈕處理 USB 熱插拔。
3. 取樣率 pop-up：16000 / 48000。
4. 套用 input device 或 sample rate 都要重建 `VoiceController`，因 `AudioRecorder` init 已固定兩者。
5. App busy 時拒絕套用並提示先停止錄音／等待辨識完成。
6. 套用後下一次錄音生效；不在 Settings 裡啟動測試錄音（v1）。

### 6.4 API Keys

1. XAI / Cerebras 使用 `NSSecureTextField`。
2. 只讀 Keychain 值供遮罩顯示；不可在 log 顯示完整／部分 key。
3. 儲存走 Keychain replace；清空走 Keychain delete，不建立空值項目。
4. 顯示目前 active source：Process Environment / env.local / Keychain / bundled config / missing。
5. 若 process env 或 env.local 有值，明確顯示「目前由較高優先來源控制，Keychain 變更不會立即生效」。
6. Keychain 改動成功後重建 STT/LLM providers + `VoiceController`，不能只改 `AppDelegate.config.apiKey`。
7. Keychain 修改也要保留舊值快照；runtime rebuild 失敗時恢復舊 Keychain 值。

### 6.5 LLM

1. LLM 修正開關：`provider = cerebras/none`。
2. Model：先提供 `gpt-oss-120b` 與可選自訂值；不要假設過時 model 一定有效。
3. Max tokens：256–8192。
4. 套用後重建 LLM provider + `VoiceController`。
5. 無 Cerebras key 時允許儲存設定，但 UI 顯示尚未就緒；實際 pipeline 仍遵守既有 fallback、不崩潰。

---

## 7. 儲存策略

| 資料 | 位置 | 規則 |
|---|---|---|
| 固定預設模式 | `config.local.json/default_mode_id` | bundle fallback 為 `pro` |
| 記住上次模式開關 | `UserDefaults/rememberLastMode` | 未設定預設 true |
| 最後模式 | `UserDefaults/lastModeId` | 只接受仍存在的 mode id |
| 詞彙開關／keyterm limit | `config.local.json/vocab.*` | 僅寫 override |
| 熱鍵 | `config.local.json/hotkey.*` | 成功註冊後才 commit |
| 輸入裝置／取樣率 | `config.local.json/recording.*` | 原子寫入，runtime swap 後生效 |
| LLM provider/model/tokens | `config.local.json/api.llm_correction.*` | 不含 API key |
| API keys | Keychain | replace/delete；永不進 JSON |
| Login item | `SMAppService` | 系統持久化 |

### ConfigLocalWriter

- 只接受 typed overrides 轉成 `[String: Any]`。
- 讀取現有 local JSON；若檔案存在但損壞，停止並提示，不可靜默覆蓋。
- deep merge 只發生在 local override 本身，不把完整 bundled config 寫回 local。
- 產生候選 effective config，先跑 `ConfigLoader.validate/build`。
- 使用 `Data.write(options: .atomic)` 寫入，並保留原始 bytes snapshot（檔案原本不存在則 snapshot 為 nil）。
- 設定檔不含 secrets；仍建議權限 600。
- 後續 runtime apply 失敗時按 snapshot 還原；還原也使用 atomic write。
- writer 內以 `NSLock`/serial queue 保護單一視窗可能發生的連續操作。

---

## 8. Runtime 套用交易

`AppDelegate.apply(_:)` 是唯一套用入口。

### 一般流程

1. 取得舊 config、local file snapshot、Keychain snapshot、hotkey specs 與 runtime references。
2. 若變更需要重建且 `voiceController.isBusy == true`，在任何寫入前拒絕。
3. 建立／驗證候選 config；API key change 以候選 secret view 組裝，不記錄 key。
4. 在 side 建立候選 `VocabStores`、STT provider、LLM provider、`VoiceController`。
5. 若熱鍵有變更，以 rollback-safe reconfigure 套用。
6. 原子寫入 config.local / Keychain。
7. 一次 swap `self.config`、providers、vocab、voiceController；重新接上 `onStateChange`。
8. 更新 Settings snapshot、Menu mode checks／狀態；log 只記設定類型與成功，不記 secret。

### 失敗流程

- 候選 build 失敗：完全不改 disk/runtime。
- 熱鍵失敗：恢復舊 hotkeys，不寫 config。
- disk/Keychain 寫入失敗：還原已改項目，不 swap runtime。
- swap 前任何錯誤：保留舊 runtime。
- swap 後不應執行會拋錯的工作；必要驗證要在 swap 前完成。

### Runtime 重建範圍

為避免 value-copy stale state，v1 對下列設定一律重建完整 provider/vocab/VoiceController runtime：

- vocab enabled / keyterm limit
- input device / sample rate
- XAI / Cerebras key
- LLM provider / model / max tokens

下列不需重建 VoiceController：

- remember last mode / last mode
- fixed default mode（只影響下次啟動 fallback）
- login item
- hotkeys（只 reconfigure `HotkeyManager`）

---

## 9. 元件細節

### ModePreferenceStore

- 封裝 UserDefaults keys，測試可注入獨立 suite。
- `startupModeId(modes:defaultId:)` 負責驗證 last/default/fallback。
- 不直接持有 `ModeManager`；AppDelegate 負責在 mode change callback 寫入。

### LoginItem

- 封裝 `SMAppService.mainApp.status/register/unregister`。
- 依本機 Xcode 26.6 SDK 正確處理 `.enabled/.notRegistered/.requiresApproval/.notFound`（沒有 `.registered` case）。
- `.requiresApproval` 時顯示並提供開啟系統「登入項目」設定。
- 不需要新增 entitlement；需在 `/Applications` 實機驗證。

### HotkeyRecorderField

- 攔截 `keyDown`，只接受 `KeyCodes` 支援的 F-key。
- modifier 至少一個；允許 Ctrl/Shift/Option/Cmd 組合。
- Escape 取消錄製。
- 顯示標準符號或一致文字，例如 `⌃F1`。
- 不以 keyCode 數值區間判斷 F1–F20。

### VoiceController busy state

- 增加 thread-safe read-only `isBusy`，由同一 lock 讀 `isRecording || isProcessing`。
- 不暴露可變 state。
- Settings 不可強制取消進行中的錄音／API 請求。

### Secrets source

- 新增不含值的 source enum，例如 `.processEnvironment/.envFile/.keychain/.config/.missing`。
- 可回報 env.local 檔案路徑，但不可回報內容。
- Keychain read/write/delete 維持 service `com.alston.VoiceKey` 與 legacy read fallback。

---

## 10. 實作階段與驗證閘門

### Phase 0 — 基線與 first-run mode

1. 讀 `AGENTS.md`、`voicekey/INDEX.md`、本 plan、`TROUBLESHOOTING-xcode.md`。
2. 確認 dirty worktree，保留既有 App Icon／簽章腳本等未提交變更。
3. `default_mode_id` 改 `pro`。
4. 新增 `ModePreferenceStore` + 啟動選擇／mode change persistence。
5. 新增測試：首次 pro、記住 last、invalid last fallback、remember off。
6. 跑完整測試。

### Phase 1 — 基礎設施

1. `SettingsModels/SettingsApplying`。
2. `ConfigLocalWriter` 原子 merge/validate/snapshot/rollback。
3. `VoiceController.isBusy`。
4. `HotkeyManager` rollback-safe reconfigure + KeyCodes reverse map。
5. `Secrets` source + delete/replace。
6. `LoginItem`。
7. 基礎設施單元測試全綠後才進 UI。

### Phase 2 — Window + General

1. Settings window/tabs skeleton。
2. MenuBar「設定…」`⌘,`。
3. General：remember last、fixed default、login item、vocab、keyterm limit、權限狀態。
4. 驗證 accessory app 能把 window 帶到前景、重開不重複建立。

### Phase 3 — Hotkeys + Recording

1. Hotkey recorder + 套用／衝突 rollback。
2. Recording device/sample rate + rescan。
3. busy guard 與 runtime rebuild。
4. 實機驗證舊熱鍵在新熱鍵失敗後仍可用。

### Phase 4 — API Keys + LLM

1. Secure fields、source indicators、Keychain transaction。
2. LLM settings。
3. provider/runtime rebuild。
4. 驗證 env.local override 警告與 secrets 不進 log/diff。

### Phase 5 — 收尾、部署與文件

1. `./test.sh`（本機需 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`）。
2. Debug + Release build；確認 34 既有測試不得退化，新測試全綠。
3. `./package.sh`，確認 self-signed leaf fingerprint 未改、strict codesign 通過。
4. 備份後更新 `/Applications/VoiceKey.app`。
5. 實機執行下列 manual matrix。
6. 更新 `voicekey/INDEX.md`、`docs/agent-progress.md`、`todo.md`。
7. 未經使用者要求，不自行 commit/push。

---

## 11. 測試計畫

### 單元測試

- `ModePreferenceStore`
  - 首次無 last → pro。
  - 有合法 last → last。
  - last 已刪除 → default。
  - remember off → default。
- `ConfigLocalWriter`
  - nested deep merge 不丟既有 override。
  - 不把 bundled config 全量寫入 local。
  - corrupt local 拒絕覆蓋。
  - candidate validation failure 不寫檔。
  - rollback 可還原 bytes／原本不存在狀態。
- `SettingsApplying`/runtime coordinator（用 mock factories）
  - busy 時零寫入。
  - candidate build 失敗保留舊 runtime。
  - success 只 swap 一次。
  - Keychain/config failure rollback。
- Hotkeys
  - F1–F20 正反向 mapping。
  - duplicate hotkey 拒絕。
  - second registration failure 恢復舊 registrations。
- Secrets
  - source priority 正確；測試不得使用真實 keys。

### 實機手動矩陣

1. 清除測試 suite 的 mode preferences／local default後，首次啟動為專業模式。
2. 切到一般對話 → 重啟 → 仍為一般對話。
3. 關閉 remember last，固定 default 選專業 → 切別的模式 → 重啟為專業。
4. Settings `⌘,` 可開、關閉後可重開、只存在一個 window。
5. 麥克風切換／USB rescan；下一次錄音使用新裝置。
6. 錄音中改 runtime setting → 拒絕且錄音不中斷。
7. 熱鍵改成功；故意選衝突組合時舊熱鍵仍可用。
8. env.local 存在時 API tab 顯示正確 source 警告。
9. LLM 關閉／開啟後 pipeline 正常；Cerebras 失敗仍 fallback raw STT。
10. Login item register/unregister/status 與系統設定一致。
11. 麥克風／輔助使用權限狀態與系統一致；按鈕可開正確設定頁。
12. 自動貼上、多 App、模式切換等既有 smoke test 不退化。

---

## 12. 風險與處理

1. **runtime value-copy stale state**：所有需要 runtime 的 config 變更走完整候選重建與 swap，不原地改 AppDelegate config。
2. **錄音中重建**：使用 `isBusy` 先拒絕；不取消、不排 pending change，讓使用者完成後再按套用。
3. **熱鍵註冊衝突**：transaction + rollback；成功前不 commit config。
4. **config.local 損壞**：拒絕覆蓋並顯示檔案路徑；保留給使用者修復。
5. **env.local/Process env 壓過 Keychain**：顯示 active source，避免「儲存成功但沒生效」錯覺。
6. **Login item 需要系統批准**：正確呈現 `.requiresApproval`，不假裝已啟用。
7. **Settings controller 過度耦合**：只依賴 protocol + snapshots；AppDelegate 保持 composition root。
8. **self-signed TCC 授權**：不得重跑強制換證；部署前後比較 certificate leaf fingerprint。
9. **Secrets 洩漏**：不印 key、不把 secure field 值寫 config、不在測試 fixture 使用真 key。

---

## 13. 新 session 完成定義

只有在下列全部成立時才算完成：

- 使用者鎖定的首次 pro／之後記住 last 行為實作且有測試。
- 五個 tab 可開啟與儲存，錯誤不破壞舊 runtime。
- input device/API/keyterm/LLM 變更確實作用於新建 provider/recorder，而非 stale copy。
- hotkey failure rollback 已實機或可控測試驗證。
- config.local 原子寫入與 rollback 測試通過。
- secrets 未出現在 repo/log/測試輸出。
- 所有既有與新增測試通過，Release build + self-signed strict verify 成功。
- `/Applications` 安裝版啟動成功，麥克風、輔助使用、錄音→STT→LLM→貼上 smoke test 無退化。
- 文件與進度已更新，未留下 `NEED_REVIEW` 未說明項目。
