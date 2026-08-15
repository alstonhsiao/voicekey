import Foundation

enum SettingsLimits {
    static let keytermMin = 0
    static let keytermMax = 10
    static let maxTokensMin = 256
    static let maxTokensMax = 8192
    static let sampleRates = [16000, 48000]
    static let defaultLLMModel = "gpt-oss-120b"
}

enum SettingsApplyError: Error, LocalizedError, Equatable {
    case busy
    case validation(String)
    case corruptLocal(String)
    case writeFailed(String)
    case runtimeBuildFailed(String)
    case hotkeyFailed
    case keychainFailed
    case loginItem(String)

    var errorDescription: String? {
        switch self {
        case .busy:
            return "目前正在錄音或辨識，請完成後再套用設定。"
        case .validation(let message):
            return message
        case .corruptLocal(let path):
            return "本機設定檔已損壞，已停止寫入以免覆蓋。請先修復或刪除：\n\(path)"
        case .writeFailed(let message):
            return "寫入設定失敗：\(message)"
        case .runtimeBuildFailed(let message):
            return "無法建立新的執行環境，已保留原設定。\(message)"
        case .hotkeyFailed:
            return "熱鍵註冊失敗，已恢復原本的熱鍵。"
        case .keychainFailed:
            return "無法更新鑰匙圈中的 API 金鑰，已恢復原值。"
        case .loginItem(let message):
            return "無法更新登入項目：\(message)"
        }
    }
}

struct SettingsModeInfo: Equatable {
    let id: String
    let name: String
    let icon: String
    var display: String { "\(icon) \(name)" }
}

struct AudioInputInfo: Equatable {
    let name: String
}

struct SettingsSnapshot {
    let modes: [SettingsModeInfo]
    let defaultModeId: String
    let currentModeId: String
    let rememberLastMode: Bool
    let lastModeId: String?

    let vocabEnabled: Bool
    let sttKeytermLimit: Int
    let layer1Path: URL
    let layer2Path: URL
    let vocabPath: URL

    let loginItemEnabled: Bool
    let loginItemStatus: LoginItemStatus

    let micAuthorized: Bool
    let accessibilityTrusted: Bool

    let hotkey: HotkeyConfig

    let sampleRate: Int
    let inputDevice: InputDeviceSpec
    let inputDevices: [AudioInputInfo]

    let xaiSource: SecretSourceInfo
    let cerebrasSource: SecretSourceInfo
    let xaiHasKeychainValue: Bool
    let cerebrasHasKeychainValue: Bool

    let llmEnabled: Bool
    let llmModel: String
    let llmMaxTokens: Int
    let llmReady: Bool
}

enum SettingsChange {
    case rememberLastMode(Bool)
    case defaultModeId(String)
    case loginItem(Bool)
    case vocabEnabled(Bool)
    case sttKeytermLimit(Int)
    case hotkeys(recordKey: String, recordModifier: String,
                 cycleKey: String, cycleModifier: String)
    case recording(sampleRate: Int, inputDevice: InputDeviceSpec)
    case apiKeys(xai: APIKeyEdit, cerebras: APIKeyEdit)
    case llm(enabled: Bool, model: String, maxTokens: Int)
}

protocol SettingsApplying: AnyObject {
    func settingsSnapshot() -> SettingsSnapshot
    func apply(_ change: SettingsChange) throws
}

/// Token handed from `rebuildRuntime` to `commitRuntime` / `discardRuntime`.
/// The host (AppDelegate) keeps the real objects in a pending slot.
struct RuntimeBuild {
    let config: AppConfig
}

/// Injectable dependencies so apply transactions can be unit-tested
/// without AppKit, Keychain, or a live VoiceController.
struct SettingsEnvironment {
    var isBusy: () -> Bool
    var config: () -> AppConfig
    var modes: () -> [Mode]
    var currentModeId: () -> String
    var modePrefs: ModePreferenceStore
    var writer: ConfigLocalWriter
    var applySecrets: (inout AppConfig, APIKeyEdit, APIKeyEdit) -> Void
    var secretSource: (String, String) -> SecretSourceInfo
    var keychainHasValue: (String) -> Bool
    var keychainRead: (String) -> String?
    var keychainReplace: (String, String) throws -> Void
    var keychainDelete: (String) throws -> Void
    var loginStatus: () -> LoginItemStatus
    var setLoginEnabled: (Bool) throws -> Void
    var micAuthorized: () -> Bool
    var accessibilityTrusted: () -> Bool
    var inputDevices: () -> [AudioInputInfo]
    var vocabPaths: () -> (URL, URL, URL)
    var applyHotkeys: (HotkeyConfig) throws -> Void
    var rebuildRuntime: (AppConfig) throws -> RuntimeBuild
    var commitRuntime: (RuntimeBuild) -> Void
    var discardRuntime: (RuntimeBuild) -> Void
    var replaceConfig: (AppConfig) -> Void
    var afterSuccess: (String) -> Void
}

final class SettingsApplyCoordinator: SettingsApplying {
    var env: SettingsEnvironment

    init(env: SettingsEnvironment) {
        self.env = env
    }

    func settingsSnapshot() -> SettingsSnapshot {
        let cfg = env.config()
        let paths = env.vocabPaths()
        let xaiRaw = ConfigLoader.rawAPIKey(account: "XAI_API_KEY")
        let cereRaw = ConfigLoader.rawAPIKey(account: "CEREBRAS_API_KEY")
        let llm = cfg.api.llmCorrection
        let cereKeyReady = !(cfg.api.llmCorrection?.cerebras?.apiKey ?? "").isEmpty
            || env.keychainHasValue("CEREBRAS_API_KEY")
            || env.secretSource("CEREBRAS_API_KEY", cereRaw).kind != .missing
        return SettingsSnapshot(
            modes: env.modes().map { SettingsModeInfo(id: $0.id, name: $0.name, icon: $0.icon) },
            defaultModeId: cfg.defaultModeId,
            currentModeId: env.currentModeId(),
            rememberLastMode: env.modePrefs.rememberLastMode,
            lastModeId: env.modePrefs.lastModeId,
            vocabEnabled: cfg.vocab.enabled,
            sttKeytermLimit: cfg.vocab.sttKeytermLimit,
            layer1Path: paths.0,
            layer2Path: paths.1,
            vocabPath: paths.2,
            loginItemEnabled: env.loginStatus().isEffectivelyEnabled,
            loginItemStatus: env.loginStatus(),
            micAuthorized: env.micAuthorized(),
            accessibilityTrusted: env.accessibilityTrusted(),
            hotkey: cfg.hotkey,
            sampleRate: cfg.recording.sampleRate,
            inputDevice: cfg.recording.inputDevice,
            inputDevices: env.inputDevices(),
            xaiSource: env.secretSource("XAI_API_KEY", xaiRaw),
            cerebrasSource: env.secretSource("CEREBRAS_API_KEY", cereRaw),
            xaiHasKeychainValue: env.keychainHasValue("XAI_API_KEY"),
            cerebrasHasKeychainValue: env.keychainHasValue("CEREBRAS_API_KEY"),
            llmEnabled: (llm?.provider ?? "none") != "none",
            llmModel: llm?.cerebras?.model ?? SettingsLimits.defaultLLMModel,
            llmMaxTokens: llm?.cerebras?.maxTokens ?? 2048,
            llmReady: cereKeyReady && (llm?.provider ?? "none") != "none"
        )
    }

    func apply(_ change: SettingsChange) throws {
        switch change {
        case .rememberLastMode(let on):
            env.modePrefs.rememberLastMode = on
            if on { env.modePrefs.noteCurrentMode(env.currentModeId()) }
            env.afterSuccess("記住上次模式")

        case .defaultModeId(let id):
            guard env.modes().contains(where: { $0.id == id }) else {
                throw SettingsApplyError.validation("找不到模式：\(id)")
            }
            let candidate = try env.writer.apply(["default_mode_id": id])
            replaceConfigKeepingSecrets(candidate)
            env.afterSuccess("固定預設模式")

        case .loginItem(let on):
            try env.setLoginEnabled(on)
            env.afterSuccess("登入時自動啟動")

        case .vocabEnabled(let on):
            try applyRuntimeOverride(["vocab": ["enabled": on]], label: "詞彙修正")

        case .sttKeytermLimit(let n):
            guard (SettingsLimits.keytermMin...SettingsLimits.keytermMax).contains(n) else {
                throw SettingsApplyError.validation(
                    "STT 關鍵詞上限必須介於 \(SettingsLimits.keytermMin)–\(SettingsLimits.keytermMax)"
                )
            }
            try applyRuntimeOverride(["vocab": ["stt_keyterm_limit": n]], label: "STT 關鍵詞上限")

        case .hotkeys(let recordKey, let recordModifier, let cycleKey, let cycleModifier):
            try applyHotkeys(recordKey: recordKey, recordModifier: recordModifier,
                             cycleKey: cycleKey, cycleModifier: cycleModifier)

        case .recording(let sampleRate, let inputDevice):
            guard SettingsLimits.sampleRates.contains(sampleRate) else {
                throw SettingsApplyError.validation("取樣率必須為 16000 或 48000")
            }
            try applyRuntimeOverride([
                "recording": [
                    "sample_rate": sampleRate,
                    "input_device": inputDevice.jsonValue(),
                ]
            ], label: "錄音裝置")

        case .apiKeys(let xai, let cerebras):
            try applyAPIKeys(xai: xai, cerebras: cerebras)

        case .llm(let enabled, let model, let maxTokens):
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SettingsApplyError.validation("LLM 模型名稱不可為空")
            }
            guard (SettingsLimits.maxTokensMin...SettingsLimits.maxTokensMax).contains(maxTokens) else {
                throw SettingsApplyError.validation(
                    "Max tokens 必須介於 \(SettingsLimits.maxTokensMin)–\(SettingsLimits.maxTokensMax)"
                )
            }
            try applyRuntimeOverride([
                "api": [
                    "llm_correction": [
                        "provider": enabled ? "cerebras" : "none",
                        "cerebras": [
                            "model": trimmed,
                            "max_tokens": maxTokens,
                        ]
                    ]
                ]
            ], label: "LLM")
        }
    }

    // MARK: - Transactions

    private func applyRuntimeOverride(_ overrides: [String: Any], label: String) throws {
        if env.isBusy() { throw SettingsApplyError.busy }
        let commit = try env.writer.prepare(overrides)
        var cfg = commit.candidate
        env.applySecrets(&cfg, .unchanged, .unchanged)
        let runtime: RuntimeBuild
        do {
            runtime = try env.rebuildRuntime(cfg)
        } catch {
            throw SettingsApplyError.runtimeBuildFailed(error.localizedDescription)
        }
        do {
            try env.writer.write(commit)
        } catch {
            env.discardRuntime(runtime)
            throw error
        }
        env.commitRuntime(runtime)
        env.afterSuccess(label)
    }

    private func applyHotkeys(recordKey: String, recordModifier: String,
                              cycleKey: String, cycleModifier: String) throws {
        guard KeyCodes.isSupportedFunctionKey(recordKey) else {
            throw SettingsApplyError.validation("錄音熱鍵只接受 F1–F20")
        }
        guard KeyCodes.isSupportedFunctionKey(cycleKey) else {
            throw SettingsApplyError.validation("切換模式熱鍵只接受 F1–F20")
        }
        guard KeyCodes.hasSupportedModifier(recordModifier) else {
            throw SettingsApplyError.validation("錄音熱鍵必須包含至少一個修飾鍵")
        }
        guard KeyCodes.hasSupportedModifier(cycleModifier) else {
            throw SettingsApplyError.validation("切換模式熱鍵必須包含至少一個修飾鍵")
        }
        let recCombo = "\(recordModifier.lowercased())+\(recordKey.lowercased())"
        let cycCombo = "\(cycleModifier.lowercased())+\(cycleKey.lowercased())"
        if recCombo == cycCombo {
            throw SettingsApplyError.validation("錄音與切換模式不能使用相同熱鍵")
        }

        let newHotkey = HotkeyConfig(
            recordKey: recordKey.uppercased(),
            recordModifier: recordModifier.lowercased(),
            modeCycleKey: cycleKey.uppercased(),
            modeCycleModifier: cycleModifier.lowercased()
        )
        let oldHotkey = env.config().hotkey
        let commit = try env.writer.prepare([
            "hotkey": [
                "record_key": newHotkey.recordKey,
                "record_modifier": newHotkey.recordModifier,
                "mode_cycle_key": newHotkey.modeCycleKey,
                "mode_cycle_modifier": newHotkey.modeCycleModifier,
            ]
        ])
        do {
            try env.applyHotkeys(newHotkey)
        } catch {
            throw SettingsApplyError.hotkeyFailed
        }
        do {
            try env.writer.write(commit)
        } catch {
            try? env.applyHotkeys(oldHotkey)
            throw error
        }
        replaceConfigKeepingSecrets(commit.candidate)
        env.afterSuccess("熱鍵")
    }

    private func applyAPIKeys(xai: APIKeyEdit, cerebras: APIKeyEdit) throws {
        if env.isBusy() { throw SettingsApplyError.busy }
        if xai == .unchanged && cerebras == .unchanged { return }

        let oldXAI = env.keychainRead("XAI_API_KEY")
        let oldCerebras = env.keychainRead("CEREBRAS_API_KEY")

        var cfg = env.config()
        env.applySecrets(&cfg, xai, cerebras)
        let runtime: RuntimeBuild
        do {
            runtime = try env.rebuildRuntime(cfg)
        } catch {
            throw SettingsApplyError.runtimeBuildFailed(error.localizedDescription)
        }

        do {
            try writeKeyEdit(account: "XAI_API_KEY", edit: xai)
            try writeKeyEdit(account: "CEREBRAS_API_KEY", edit: cerebras)
        } catch {
            restoreKey("XAI_API_KEY", oldXAI)
            restoreKey("CEREBRAS_API_KEY", oldCerebras)
            env.discardRuntime(runtime)
            throw SettingsApplyError.keychainFailed
        }

        env.commitRuntime(runtime)
        env.afterSuccess("API 金鑰")
    }

    private func writeKeyEdit(account: String, edit: APIKeyEdit) throws {
        switch edit {
        case .unchanged:
            return
        case .set(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SettingsApplyError.validation("API 金鑰不可為空")
            }
            try env.keychainReplace(account, trimmed)
        case .clear:
            try env.keychainDelete(account)
        }
    }

    private func restoreKey(_ account: String, _ value: String?) {
        if let value, !value.isEmpty {
            try? env.keychainReplace(account, value)
        } else {
            try? env.keychainDelete(account)
        }
    }

    private func replaceConfigKeepingSecrets(_ candidate: AppConfig) {
        var cfg = candidate
        env.applySecrets(&cfg, .unchanged, .unchanged)
        env.replaceConfig(cfg)
    }
}
