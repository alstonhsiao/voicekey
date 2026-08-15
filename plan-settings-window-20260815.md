# VoiceKey Settings Window 實作計畫

> **狀態**：待使用者確認後，在新 session 執行。
> **前置條件**：已完成 start/stop 死結修復（commit `f430e8d`）；GOTCHAS 已改名 TROUBLESHOOTING。
> **預估規模**：~900 行 Swift，8 個新檔案 + 5 個既有檔案修改。

---

## 目標

在選單列 app 加一個「⚙️ 設定…」入口，開獨立 `NSWindow`，用 `NSTabViewController` 分 5 個 tab，讓使用者不編輯 JSON 就能改設定。所有變更即時生效（不需重啟），且只寫 `config.local.json`（不改 bundle 內 `config.json`）。API keys 走 Keychain。開機自動執行用 `SMAppService`（macOS 13+ 官方 API）。

---

## 現有架構約束（探索結果摘要）

| 約束 | 影響 |
|---|---|
| `config.local.json` 目前是 read-only（`ConfigLoader.load()` 只讀不寫） | 需新增 `ConfigLocalWriter` |
| `HotkeyManager` 沒有 `unregisterAll()` | 需新增，才能 runtime 換熱鍵 |
| `AppConfig.recording` / `hotkey` / `vocab` 都是 `let`（不可變） | 改這些需 reload config + 重建相關元件 |
| `VocabStores.layer3` 在 `enabled=false` 時為 nil，無 runtime toggle | 需重建 `VocabStores` |
| API keys 已有 `Secrets.keychainWrite(account:value:)` | 直接用，不需新寫入邏輯 |
| `project.yml` 用目錄 glob（`sources: - path: VoiceKey`） | 新 .swift 檔自動包含，改 `project.yml` 不需要 |
| `SMAppService` 需 macOS 13+ | deployment target 已是 13.0 ✓ |
| app 是 `LSUIElement`（accessory policy） | 開 Settings 視窗時需 `NSApp.activate(ignoringOtherApps: true)` |
| `AppDelegate` 持有所有元件 | Settings 需透過 delegate 或 protocol 取得元件參考 |
| `MenuBarController` 用 `MenuAction` retain closure | Settings 選單項目沿用同一 pattern |

---

## 新增檔案清單

```
voicekey/VoiceKey/
├── Settings/
│   ├── SettingsWindowController.swift    # NSWindow + NSTabViewController 容器
│   ├── SettingsTabViewController.swift   # 共用 base：tab 圖示 + view 載入 helper
│   ├── GeneralTabViewController.swift    # Tab 1：開機自動執行 + 預設模式 + 詞彙開關
│   ├── HotkeyTabViewController.swift     # Tab 2：熱鍵錄製（record key + 修飾鍵）
│   ├── RecordingTabViewController.swift  # Tab 3：輸入裝置下拉 + 取樣率
│   ├── APIKeysTabViewController.swift    # Tab 4：XAI / Cerebras key（遮罩輸入）
│   ├── LLMTabViewController.swift        # Tab 5：LLM 修正開關 + provider + model + max_tokens
│   └── HotkeyRecorderField.swift         # NSTextField subclass 攔截 keyDown 做熱鍵錄製
├── Core/
│   ├── ConfigLocalWriter.swift           # 安全寫入 config.local.json（deep merge 後只寫覆蓋 key）
│   └── LoginItem.swift                   # 封裝 SMAppService register/unregister/status
```

## 既有檔案修改清單

| 檔案 | 修改內容 |
|---|---|
| `AppDelegate.swift` | 持有 `SettingsWindowController?`；加 `openSettings()` 方法；加 `applyConfigChanges()` 重建熱鍵/錄音/詞彙/provider |
| `MenuBarController.swift` | 在「關於」和「結束程式」之間加「⚙️ 設定…」選單項目 |
| `HotkeyManager.swift` | 新增 `unregisterAll()` 方法 |
| `Config.swift` | `HotkeyConfig` / `RecordingConfig` / `VocabConfig` 改為 `var`（支援重建） |
| `AGENTS.md` | Quick Map 新增 Settings 相關 spoke 條目（如果需要） |

---

## 詳細設計

### 1. SettingsWindowController.swift

```
final class SettingsWindowController: NSWindowController
```

- `init()` 時建 `NSWindow`（title: "VoiceKey 設定"，styleMask: `.titled + .closable + .miniaturizable`，不加 `.resizable` 固定寬度 480pt）
- 內容設為 `NSTabViewController`，5 個 tab item（`NSTabViewItem`）
- 每個 tab 的 `viewController` 是對應的 `*TabViewController`
- tab 樣式用 `.topTabs`（標準 macOS tab bar）
- `showWindow(nil)` 前呼叫 `NSApp.activate(ignoringOtherApps: true)`（因為 app 是 accessory policy）
- 視窗關閉後不釋放（保持狀態），下次 open 重用同一 instance

### 2. GeneralTabViewController.swift

```
final class GeneralTabViewController: NSViewController
```

**UI 元件**（由上到下）：

1. **開機自動執行** — `NSButton(checkbox)`
   - 勾選 → `LoginItem.enable()` → `SMAppService.mainApp.register()`
   - 取消 → `LoginItem.disable()` → `SMAppService.mainApp.unregister()`
   - 初始狀態 → `LoginItem.isEnabled` → `SMAppService.mainApp.status == .registered`
   - 失敗時顯示 `NSAlert`（"無法設定開機自動執行：\(error)"）
   - **不需寫 config** — 系統自行持久化

2. **預設模式** — `NSPopUpButton`
   - 選項來自 `ModeManager.all`（`mode.display` 為標題，`mode.id` 為 tag）
   - 初始選中 `ModeManager.current.id`
   - 改選 → 寫 `config.local.json` 的 `default_mode_id` + `ModeManager.setById(id)`
   - 即時生效：下次 app 啟動也用新預設模式

3. **詞彙修正** — `NSButton(checkbox)`
   - 勾選 → 寫 `config.local.json` 的 `vocab.enabled = true`
   - 取消 → 寫 `vocab.enabled = false`
   - 即時生效：呼叫 `AppDelegate.applyConfigChanges()` 重建 `VocabStores`（`layer3` 依 `enabled` 決定 nil 與否）
   - **注意**：重建 `VocabStores` 需重建 `VoiceController`（因為 `VoiceController` 持有 `VocabStores`），此為較重操作但可接受

4. **STT 關鍵詞上限** — `NSTextField` + stepper
   - 範圍 0–50，初始值 `config.vocab.sttKeytermLimit`
   - 改值 → 寫 `config.local.json` 的 `vocab.stt_keyterm_limit`
   - 即時生效：更新 `AppConfig.vocab.sttKeytermLimit`（改 `var`）

### 3. HotkeyTabViewController.swift

**UI 元件**：

1. **錄音熱鍵** — `HotkeyRecorderField`（自訂 NSTextField）+ 顯示目前組合
   - 預設顯示 `CTRL+F1`（從 `config.hotkey.recordModifier` + `config.hotkey.recordKey` 組合）
   - 點擊進入錄製模式 → 使用者按任意鍵 → 攔截 keyDown → 顯示新組合
   - 支援修飾鍵：Ctrl / Shift / Option / Cmd + F1–F20
   - 不支援字母鍵（只支援功能鍵，與 `KeyCodes.functionKeys` 範圍一致）

2. **切模式熱鍵** — 同上，對應 `mode_cycle_key` / `mode_cycle_modifier`

3. **「套用」按鈕** — 點擊後：
   - 寫 `config.local.json` 的 `hotkey` 區塊
   - 呼叫 `HotkeyManager.unregisterAll()` → 重新 `register()` 兩組熱鍵
   - 顯示成功/失敗訊息

**為什麼用「套用」按鈕而不是即時生效**：熱鍵變更涉及 unregister + register，如果使用者邊錄邊改會频繁觸發。用「套用」按鈕讓使用者確認後一次套用。

### 4. HotkeyRecorderField.swift

```
final class HotkeyRecorderField: NSTextField
```

- 繼承 `NSTextField`，override `keyDown(with:)`
- `isEditable = true`，但不顯示游標（用 `style = .rounded` + 灰底顯示「按下要錄製的鍵…」）
- 攔截 `event.modifierFlags` + `event.keyCode`：
  - 只接受功能鍵 F1–F20（`keyCode` 在 `kVK_F1`...`kVK_F20` 範圍）
  - 修飾鍵从 `event.modifierFlags` 提取：`control` / `shift` / `option` / `command`
  - 不接受單獨修飾鍵按下（需配合功能鍵）
- 錄到有效組合後 → 更新顯示文字（如 "CTRL + F1"）→ 設 `isEditable = false`
- 提供 `var currentKey: String` 和 `var currentModifier: String` 給 controller 讀取
- 反查 `KeyCodes.functionKeys` 把 keyCode 轉回 key name

### 5. RecordingTabViewController.swift

**UI 元件**：

1. **輸入裝置** — `NSPopUpButton`
   - 選項：呼叫 `CoreAudioDevices.allInputDevices()` 列出所有裝置
   - 加一個「系統預設」選項在最上面
   - 初始選中：依 `config.recording.inputDevice` 解析（`.systemDefault` → 第一項；`.name` → 比對；`.candidates` → 第一個找到的）
   - 改選 → 寫 `config.local.json` 的 `recording.input_device`（裝置名稱字串）
   - 即時生效：更新 `AppConfig.recording.inputDevice` → 下次錄音 `AudioRecorder.start()` 用新裝置
   - **不需重建** `AudioRecorder`（它在 `VoiceController` 內，每次 `start()` 都建新 engine 並讀 `config.recording.inputDevice`）

2. **取樣率** — `NSPopUpButton`（16000 / 48000）
   - 初始值 `config.recording.sampleRate`
   - 改值 → 寫 `config.local.json` 的 `recording.sample_rate`
   - 即時生效：更新 `AppConfig.recording.sampleRate`（需改 `var`）
   - 注意：`AudioRecorder.targetFormat` 在 `init` 時固定，改 sampleRate 需重建 `AudioRecorder` → 重建 `VoiceController`。**或者**改 `AudioRecorder` 讓 `targetFormat` 延遲計算。**建議方案**：簡化為重建 `VoiceController`（与詞彙開關同一重建路徑）。

3. **重新掃描裝置按鈕** — 重新呼叫 `CoreAudioDevices.allInputDevices()` 刷新下拉選單（USB 裝置可能熱插拔）

### 6. APIKeysTabViewController.swift

**UI 元件**：

1. **XAI API Key** — `NSSecureTextField`（遮罩顯示）
   - 初始值：從 `Secrets.keychainRead(account: "XAI_API_KEY")` 讀取；若 nil 則空
   - placeholder: "xai-..."
   - 失焦或按「儲存」→ `Secrets.keychainWrite(account: "XAI_API_KEY", value: newText)`
   - 即時生效：更新 `AppConfig.api.grok.apiKey`（已是 `var`）→ 下次 STT 呼叫用新 key

2. **Cerebras API Key** — `NSSecureTextField`
   - 同上，account: `"CEREBRAS_API_KEY"`
   - 更新 `AppConfig.api.llmCorrection?.cerebras?.apiKey`

3. **「測試連線」按鈕**（選配，v1 可不做）
   - 發一個簡單的 API request 確認 key 有效

**為什麼用 Keychain 而非 env.local**：
- `Secrets.keychainWrite` 已存在，不需新寫入邏輯
- Keychain 優先序低於 env.local，如果使用者同時有 env.local，GUI 改的 key 不會生效（env.local 蓋過 keychain）
- **處理方式**：如果 `Secrets.loadEnv()` 讀到 env.local 有值，在 UI 顯示提示「⚠️ env.local 已設定此 key，GUI 變更不會生效。請刪除 env.local 中的對應行。」
- 儲存時仍寫 Keychain（如果使用者刪了 env.local，keychain 的值就會生效）

### 7. LLMTabViewController.swift

**UI 元件**：

1. **LLM 修正** — `NSButton(checkbox)`（啟用/停用）
   - 勾選 → `config.local.json` 的 `api.llm_correction.provider = "cerebras"`
   - 取消 → `api.llm_correction.provider = "none"`
   - 即時生效：重建 `LLMCorrectionProvider`（`LLMCorrectionProviders.build()`）

2. **Model** — `NSPopUpButton` 或 `NSTextField`
   - 預設選項：`gpt-oss-120b`、`llama3.3-70b`（下拉）或自訂輸入
   - 改值 → 寫 `config.local.json` 的 `api.llm_correction.cerebras.model`
   - 即時生效：重建 provider

3. **Max Tokens** — `NSTextField` + stepper
   - 範圍 256–8192，初始值 `config.llmCorrection.cerebras.maxTokens`
   - 改值 → 寫 `config.local.json` 的 `api.llm_correction.cerebras.max_tokens`

### 8. ConfigLocalWriter.swift

```
enum ConfigLocalWriter
```

- `static func write(overrides: [String: Any])` — 安全寫入 `config.local.json`
- 讀取現有 `config.local.json`（如果存在）→ `deepMerge(existing, overrides)` → 寫回
- 用 `JSONSerialization` with `.prettyPrinted` + `.sortedKeys` 輸出
- 寫入前先備份（`config.local.json.bak`）
- 與 `ConfigLoader.deepMerge` 共用同一邏輯（extract 到共用 static func 或直接呼叫 `ConfigLoader.deepMerge`）

**只寫覆蓋的 key**：例如只改熱鍵，就傳 `["hotkey": ["record_key": "F2", ...]]`，其他 key 不動。deep merge 確保既有值不丟。

### 9. LoginItem.swift

```
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .registered
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
```

- `SMAppService.mainApp.status`：`.notRegistered` / `.registered` / `.requiresApproval` / `.notFound`
- `register()` 可能丟 `NSError`（domain `SMAppServiceErrorDomain`）
- `register()` 後系統可能顯示「允許在背景新增登入項目」對話框（macOS 13 行為）
- 不需寫 config — 系統自行持久化 register/unregister 狀態
- 不需改 entitlements（unsandboxed app 不需特殊 entitlement）

---

## 既有檔案修改細節

### AppDelegate.swift

新增：

```swift
private var settingsController: SettingsWindowController?

func openSettings() {
    if settingsController == nil {
        settingsController = SettingsWindowController(
            config: config!,           // 傳入可變參考
            modeManager: modeManager!,
            // 其他需要的元件參考
        )
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsController?.showWindow(nil)
}
```

新增 `applyConfigChanges(_ config: AppConfig)` 方法：
- 重新讀取 `config.local.json` + `Secrets.apply` → 取得新 `AppConfig`
- 重建需要更換的元件（依哪些設定變了）：
  - **熱鍵變了** → `hotkeyManager?.unregisterAll()` → 重新 register
  - **詞彙開關或取樣率變了** → 重建 `VocabStores` + `VoiceController`
  - **LLM 設定變了** → 重建 `LLMCorrectionProvider`（需讓 `VoiceController` 能換 provider，或重建 `VoiceController`）
  - **API key 變了** → 更新 `config.api` 的對應欄位（已是 `var`），不需重建（下次 API 呼叫用新 key）
- 更新 `self.config = newConfig`

**簡化策略**：v1 一律重建 `VoiceController`（除了 API key 只更新 config）。重建成本低（只是物件 init，不涉及麥克風/網路），且避免局部更新的複雜度。

### MenuBarController.swift

在 `rebuildMenu()` 裡「關於 VoiceKey」之前加：

```swift
menu.addItem(actionItem("⚙️ 設定…") { [weak self] in
    // 需要拿到 AppDelegate 參考
    (NSApp.delegate as? AppDelegate)?.openSettings()
})
```

### HotkeyManager.swift

新增：

```swift
func unregisterAll() {
    for ref in refs where ref != nil {
        UnregisterEventHotKey(ref)
    }
    refs.removeAll()
    actions.removeAll()
    // handlerRef 保留 — 不需重新安裝 EventHandler
}
```

### Config.swift

把 `HotkeyConfig`、`RecordingConfig`、`VocabConfig` 的 `let` 欄位改為 `var`：

```swift
struct HotkeyConfig {
    var recordKey: String       // was let
    var recordModifier: String
    var modeCycleKey: String
    var modeCycleModifier: String
}

struct RecordingConfig {
    var sampleRate: Int         // was let
    var channels: Int
    var inputDevice: InputDeviceSpec
}

struct VocabConfig {
    var enabled: Bool           // was let
    var file: String
    var sttKeytermLimit: Int
    var match: VocabMatchConfig
}
```

`AppConfig` 的 `recording` / `hotkey` / `vocab` 也從 `let` 改 `var`。

---

## 即時生效策略（按設定分類）

| 設定 | 即時生效方式 | 需重建？ |
|---|---|---|
| 預設模式 | `ModeManager.setById()` | 否 |
| 詞彙開關 | 重建 `VocabStores` + `VoiceController` | 是（v1 簡化） |
| STT keyterm 上限 | 更新 `config.vocab.sttKeytermLimit` | 否 |
| 熱鍵 | `unregisterAll()` + `register()` | 否 |
| 輸入裝置 | 更新 `config.recording.inputDevice` | 否（`AudioRecorder` 每次 `start()` 建新 engine） |
| 取樣率 | 重建 `VoiceController`（`targetFormat` 在 init 固定） | 是 |
| API keys | 更新 `config.api.*.apiKey` | 否 |
| LLM 開關/model/tokens | 重建 `LLMCorrectionProvider` | 需讓 `VoiceController` 能換，或重建 |
| 開機自動執行 | `SMAppService.register/unregister` | 否 |

**v1 簡化**：除了「預設模式」「API keys」「熱鍵」「輸入裝置」「開機自動執行」可即時更新外，其餘一律走 `AppDelegate.applyConfigChanges()` → 重建 `VoiceController`。重建時如果正在錄音或辨識，先等完成（或直接放棄此次，因為使用者正在改設定不太可能同時錄音）。

---

## 儲存策略

| 設定類型 | 儲存位置 | 機制 |
|---|---|---|
| 預設模式 | `config.local.json` → `default_mode_id` | `ConfigLocalWriter.write` |
| 詞彙開關 | `config.local.json` → `vocab.enabled` | `ConfigLocalWriter.write` |
| STT keyterm 上限 | `config.local.json` → `vocab.stt_keyterm_limit` | `ConfigLocalWriter.write` |
| 熱鍵 | `config.local.json` → `hotkey.*` | `ConfigLocalWriter.write` |
| 輸入裝置 | `config.local.json` → `recording.input_device` | `ConfigLocalWriter.write` |
| 取樣率 | `config.local.json` → `recording.sample_rate` | `ConfigLocalWriter.write` |
| API keys | **Keychain** | `Secrets.keychainWrite` |
| LLM 設定 | `config.local.json` → `api.llm_correction.*` | `ConfigLocalWriter.write` |
| 開機自動執行 | **系統 SMAppService** | `SMAppService.mainApp.register/unregister` |

---

## 實作順序（建議分 5 個 PR / commit）

### Phase 1：基礎設施
1. `Config.swift` — `let` → `var` 改動
2. `HotkeyManager.swift` — 新增 `unregisterAll()`
3. `ConfigLocalWriter.swift` — 新增
4. `LoginItem.swift` — 新增
5. 跑 `./test.sh` 確認 34 測試仍綠

### Phase 2：Settings 視窗骨架 + General tab
1. `SettingsWindowController.swift` — 視窗 + tab 容器
2. `GeneralTabViewController.swift` — 開機自動執行 + 預設模式 + 詞彙開關 + keyterm 上限
3. `AppDelegate.swift` — 加 `openSettings()` + `applyConfigChanges()`
4. `MenuBarController.swift` — 加「⚙️ 設定…」選單項目
5. Build + 手動驗證：選單列能開 Settings 視窗、General tab 可操作

### Phase 3：Hotkey tab
1. `HotkeyRecorderField.swift` — 熱鍵錄製欄位
2. `HotkeyTabViewController.swift` — 錄音鍵 + 切模式鍵 + 套用按鈕
3. Build + 手動驗證：改熱鍵後套用生效

### Phase 4：Recording + API Keys + LLM tab
1. `RecordingTabViewController.swift` — 裝置下拉 + 取樣率
2. `APIKeysTabViewController.swift` — 兩個 secure text field
3. `LLMTabViewController.swift` — 開關 + model + max_tokens
4. Build + 手動驗證：所有 tab 可操作、變更生效

### Phase 5：收尾
1. `AppDelegate.applyConfigChanges()` — 完整重建邏輯
2. 邊界 case 處理（正在錄音時改設定、config.local.json 寫入失敗、SMAppService 失敗）
3. 更新 `voicekey/INDEX.md`（Settings 功能說明）
4. 更新 `docs/agent-progress.md`
5. `./test.sh` + `./build.sh` 全綠
6. 重新簽章安裝到 `/Applications`，實機驗證

---

## 風險與注意事項

1. **`SMAppService.mainApp.register()` 首次呼叫** — macOS 13 可能跳系統對話框「允許在背景新增登入項目」。這是正常行為，使用者需點「允許」。Settings UI 要在勾選後等 register() 返回再更新 checkbox 狀態（避免勾了但失敗時 UI 顯示不對）。

2. **env.local 與 Keychain 衝突** — 如果使用者在 `~/Library/Application Support/VoiceKey/env.local` 有 `XAI_API_KEY=...`，GUI 改的 key 不會生效（env.local 優先序高於 keychain）。API Keys tab 需偵測並顯示警告。

3. **config.local.json 寫入競爭** — 如果同時有兩個地方寫（不太可能，因為 Settings 是單一視窗），需確保 `ConfigLocalWriter` 的讀-改-寫是原子的。用 `FileCoordination` 或簡單的 `NSLock` 保護。

4. **重建 VoiceController 時正在錄音** — 如果使用者改設定時正好在錄音，重建 `VoiceController` 會丟掉正在進行的錄音。處理方式：`applyConfigChanges()` 前檢查 `voiceController` 狀態，如果在錄音/辨識中則提示「請先停止錄音再變更設定」或直接忽略重建（標記 pending，等下次 idle 時再重建）。**建議**：v1 直接檢查狀態，如果在忙碌中就顯示警告不執行。

5. **HotkeyRecorderField 只支援功能鍵** — 現有 `KeyCodes.functionKeys` 只有 F1–F20。如果未來要支援字母鍵，需擴充 `KeyCodes`。v1 維持只支援功能鍵，UI 顯示「請按 F1–F20 功能鍵」。

6. **`SMAppService` 不需改 `project.yml`** — `import ServiceManagement` 時系統 framework 自動 link，不需手動加 dependency。

7. **LSUIElement app 開視窗** — accessory policy app 開 `NSWindow` 需 `NSApp.activate(ignoringOtherApps: true)`，否則視窗可能不出現在前景。已在 `openSettings()` 處理。

8. **測試** — Settings UI 大部分是 GUI 操作，不易寫單元測試。可測試的部分：
   - `ConfigLocalWriter.write()` → 讀回驗證 deep merge 正確
   - `LoginItem.isEnabled` 狀態查詢
   - `HotkeyManager.unregisterAll()` 後 refs/actions 清空
   - 既有 34 測試不能退化

---

## 不在這次範圍內（明確排除）

- **模式編輯**（prompt / keyterms / regex_rules）— 太複雜，維持 JSON 編輯
- **詞彙內容編輯** — 維持外部編輯器子選單
- **HUD 設定** — config.json 有 `ui.hud_*` 但程式碼沒實作 HUD，等 HUD 實作後再加
- **API key 測試連線按鈕** — v1 不做，v2 選配
- **字母鍵熱鍵** — v1 只支援 F1–F20
- **多語系 UI** — 全繁體中文，不做 i18n