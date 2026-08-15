import AppKit
import AVFoundation

/// Application lifecycle. Wires together all components and is the only
/// `SettingsApplying` implementation (composition root).
final class AppDelegate: NSObject, NSApplicationDelegate, SettingsApplying {
    private var menuBar: MenuBarController?
    private(set) var config: AppConfig?
    private(set) var modeManager: ModeManager?
    private var voiceController: VoiceController?
    private var hotkeyManager: HotkeyManager?
    private var sessionLogger: SessionLogger?
    private var vocab: VocabStores?
    private var transcribe: TranscribeProvider?
    private var llm: LLMCorrectionProvider?
    private var settingsWindow: SettingsWindowController?
    private let modePrefs = ModePreferenceStore()
    private var coordinator: SettingsApplyCoordinator?
    private var pendingRuntime: (transcribe: TranscribeProvider,
                                 llm: LLMCorrectionProvider?,
                                 vocab: VocabStores,
                                 voiceController: VoiceController)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest, skip full app setup (no hotkeys / mic / config side effects).
        if NSClassFromString("XCTestCase") != nil { return }

        if !SingleInstance.acquire() {
            AppLog.warn("⚠️ VoiceKey 已在執行中，結束本實例")
            NSApp.terminate(nil)
            return
        }

        AppLog.info(String(repeating: "=", count: 50))
        AppLog.info("🎤 VoiceKey（Xcode 原生版）啟動")

        let cfg: AppConfig
        let mm: ModeManager
        let transcribe: TranscribeProvider
        let llm: LLMCorrectionProvider?
        let vocab: VocabStores
        do {
            var loaded = try ConfigLoader.load()
            Secrets.apply(to: &loaded)
            let vs = VocabStores(config: loaded)
            cfg = loaded
            vocab = vs
            let startupId = modePrefs.startupModeId(modes: loaded.modes, defaultId: loaded.defaultModeId)
            mm = ModeManager(modes: loaded.modes, defaultId: startupId)
            transcribe = try TranscribeProviders.build(loaded.api)
            llm = LLMCorrectionProviders.build(loaded.api)
            self.config = cfg
            self.modeManager = mm
            self.vocab = vs
            self.transcribe = transcribe
            self.llm = llm
            logSummary(cfg, mm)
        } catch {
            AppLog.error("❌ 設定/Provider 初始化失敗：\(error)")
            NSApp.terminate(nil)   // match Python: exit on invalid config
            return
        }

        let sessionLogger = SessionLogger()
        self.sessionLogger = sessionLogger
        let vc = VoiceController(config: cfg, modeManager: mm,
                                 transcribe: transcribe, llm: llm, vocab: vocab,
                                 sessionLogger: sessionLogger)
        self.voiceController = vc

        let mb = MenuBarController(modeManager: mm, vocab: vocab) { [weak self] in
            self?.openSettings()
        }
        self.menuBar = mb
        vc.onStateChange = { [weak mb] state in mb?.setState(state) }
        mm.onChange { [weak self, weak mb] mode in
            self?.modePrefs.noteCurrentMode(mode.id)
            mb?.refreshModeChecks()
        }

        logInputDevices(cfg)
        setupHotkeys(cfg)
        installCoordinator()
        requestMicrophoneAccess()
        checkAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SingleInstance.release()
    }

    // MARK: - SettingsApplying

    func settingsSnapshot() -> SettingsSnapshot {
        coordinator?.settingsSnapshot() ?? fallbackSnapshot()
    }

    func apply(_ change: SettingsChange) throws {
        guard let coordinator else {
            throw SettingsApplyError.validation("設定系統尚未就緒")
        }
        try coordinator.apply(change)
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(applier: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
    }

    // MARK: - Coordinator

    private func installCoordinator() {
        let writer = ConfigLocalWriter()
        coordinator = SettingsApplyCoordinator(env: SettingsEnvironment(
            isBusy: { [weak self] in self?.voiceController?.isBusy ?? false },
            config: { [weak self] in
                self?.config ?? AppConfig(
                    modes: [], defaultModeId: "pro",
                    api: APIConfig(provider: "grok", temperature: 0,
                                   openai: ProviderEndpoint(apiKey: "", model: "", endpoint: ""),
                                   grok: ProviderEndpoint(apiKey: "", model: "", endpoint: ""),
                                   groq: ProviderEndpoint(apiKey: "", model: "", endpoint: ""),
                                   llmCorrection: nil),
                    recording: RecordingConfig(sampleRate: 16000, channels: 1, inputDevice: .systemDefault),
                    hotkey: HotkeyConfig(recordKey: "F1", recordModifier: "ctrl",
                                         modeCycleKey: "F10", modeCycleModifier: "ctrl"),
                    vocab: VocabConfig(enabled: false, file: "user_vocab.json", sttKeytermLimit: 10,
                                       match: VocabMatchConfig(useTone: false, requireSurnameCharSame: false, minTermLen: 2))
                )
            },
            modes: { [weak self] in self?.modeManager?.all ?? [] },
            currentModeId: { [weak self] in self?.modeManager?.current.id ?? "" },
            modePrefs: modePrefs,
            writer: writer,
            applySecrets: { cfg, xai, cerebras in
                Secrets.apply(to: &cfg, xaiEdit: xai, cerebrasEdit: cerebras)
            },
            secretSource: { account, configValue in
                Secrets.source(for: account, configValue: configValue)
            },
            keychainHasValue: { Secrets.keychainHasValue(account: $0) },
            keychainRead: { Secrets.keychainRead(account: $0) },
            keychainReplace: { account, value in
                if !Secrets.keychainReplace(account: account, value: value) {
                    throw SettingsApplyError.keychainFailed
                }
            },
            keychainDelete: { account in
                if !Secrets.keychainDelete(account: account) {
                    throw SettingsApplyError.keychainFailed
                }
            },
            loginStatus: { LoginItem.currentStatus() },
            setLoginEnabled: { try LoginItem.setEnabled($0) },
            micAuthorized: {
                AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            },
            accessibilityTrusted: { Paste.isAccessibilityTrusted() },
            inputDevices: {
                CoreAudioDevices.allInputDevices().map { AudioInputInfo(name: $0.name) }
            },
            vocabPaths: { [weak self] in
                if let v = self?.vocab {
                    return (v.layer1Path, v.layer2Path, v.vocabPath)
                }
                let dir = AppPaths.appSupport
                return (dir.appendingPathComponent("layer1_keyterms.json"),
                        dir.appendingPathComponent("layer2_corrections.json"),
                        dir.appendingPathComponent("user_vocab.json"))
            },
            applyHotkeys: { [weak self] hk in
                try self?.registerHotkeys(hk)
            },
            rebuildRuntime: { [weak self] cfg in
                try self?.rebuildRuntime(from: cfg) ?? {
                    throw SettingsApplyError.runtimeBuildFailed("AppDelegate 已釋放")
                }()
            },
            commitRuntime: { [weak self] build in
                self?.commitRuntime(build)
            },
            discardRuntime: { [weak self] _ in
                self?.pendingRuntime = nil
            },
            replaceConfig: { [weak self] cfg in
                self?.config = cfg
            },
            afterSuccess: { [weak self] label in
                AppLog.info("⚙️ 已套用設定：\(label)")
                self?.settingsWindow?.reloadFromApplier()
            }
        ))
    }

    private func rebuildRuntime(from cfg: AppConfig) throws -> RuntimeBuild {
        guard let mm = modeManager, let sessionLogger else {
            throw SettingsApplyError.runtimeBuildFailed("執行環境尚未就緒")
        }
        let transcribe = try TranscribeProviders.build(cfg.api)
        let llm = LLMCorrectionProviders.build(cfg.api)
        let vocab = VocabStores(config: cfg)
        let vc = VoiceController(config: cfg, modeManager: mm,
                                 transcribe: transcribe, llm: llm, vocab: vocab,
                                 sessionLogger: sessionLogger)
        pendingRuntime = (transcribe, llm, vocab, vc)
        return RuntimeBuild(config: cfg)
    }

    private func commitRuntime(_ build: RuntimeBuild) {
        guard let pending = pendingRuntime else { return }
        pendingRuntime = nil
        self.config = build.config
        self.transcribe = pending.transcribe
        self.llm = pending.llm
        self.vocab = pending.vocab
        self.voiceController = pending.voiceController
        voiceController?.onStateChange = { [weak self] state in
            self?.menuBar?.setState(state)
        }
        menuBar?.setState(.idle)
    }

    // MARK: - Hotkeys

    private func setupHotkeys(_ cfg: AppConfig) {
        hotkeyManager = HotkeyManager()
        do {
            try registerHotkeys(cfg.hotkey)
            AppLog.info("⌨️ 熱鍵註冊：成功（免「輸入監控」授權）")
        } catch {
            AppLog.warn("⚠️ 熱鍵註冊：部分失敗（見警告）")
        }
    }

    private func registerHotkeys(_ hk: HotkeyConfig) throws {
        guard let manager = hotkeyManager else {
            throw SettingsApplyError.hotkeyFailed
        }
        guard let recCode = KeyCodes.keyCode(for: hk.recordKey) else {
            AppLog.warn("⚠️ 未知錄音熱鍵：\(hk.recordKey)")
            throw SettingsApplyError.hotkeyFailed
        }
        guard let cycCode = KeyCodes.keyCode(for: hk.modeCycleKey) else {
            AppLog.warn("⚠️ 未知切模式熱鍵：\(hk.modeCycleKey)")
            throw SettingsApplyError.hotkeyFailed
        }
        let specs = [
            HotkeySpec(keyCode: recCode,
                       modifiers: KeyCodes.modifierFlags(hk.recordModifier),
                       action: { [weak self] in self?.voiceController?.toggleRecord() }),
            HotkeySpec(keyCode: cycCode,
                       modifiers: KeyCodes.modifierFlags(hk.modeCycleModifier),
                       action: { [weak self] in self?.voiceController?.cycleMode() }),
        ]
        if !manager.reconfigure(specs) {
            throw SettingsApplyError.hotkeyFailed
        }
    }

    // MARK: - Microphone permission

    private func requestMicrophoneAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            AppLog.info("🎤 麥克風權限：已授權")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                AppLog.info("🎤 麥克風權限：\(granted ? "已授權" : "被拒")")
            }
        case .denied, .restricted:
            AppLog.warn("⚠️ 麥克風權限被拒/受限 → 系統設定 → 隱私權與安全性 → 麥克風")
        @unknown default:
            break
        }
    }

    // MARK: - Accessibility permission (for CGEvent paste)

    private func checkAccessibility() {
        if Paste.isAccessibilityTrusted() {
            AppLog.info("♿️ 輔助使用權限：已授權（可自動貼上）")
        } else {
            AppLog.warn("⚠️ 輔助使用權限：未授權 → 將跳出系統對話框；辨識文字會先留在剪貼簿")
            Paste.promptAccessibilityIfNeeded()
        }
    }

    // MARK: - Diagnostics

    private func logInputDevices(_ cfg: AppConfig) {
        let devices = CoreAudioDevices.allInputDevices()
        let list = devices.map { "\($0.id):\($0.name)" }.joined(separator: " | ")
        AppLog.info("🎙️ 可用輸入裝置：\(list.isEmpty ? "(無)" : list)")
        if let id = CoreAudioDevices.find(cfg.recording.inputDevice), let name = CoreAudioDevices.deviceName(id) {
            AppLog.info("🎙️ 解析錄音裝置：\(id):\(name)")
        } else {
            AppLog.info("🎙️ 解析錄音裝置：系統預設輸入")
        }
    }

    private func logSummary(_ cfg: AppConfig, _ mm: ModeManager) {
        AppLog.info("   模式數：\(mm.all.count)（\(mm.all.map { $0.id }.joined(separator: ", "))）")
        AppLog.info("   目前模式：\(mm.current.display)")
        AppLog.info("   STT Provider：\(cfg.api.provider)")
        let grokReady = !cfg.api.grok.apiKey.isEmpty
        let cereReady = cfg.api.llmCorrection?.cerebras.map { !$0.apiKey.isEmpty } ?? false
        AppLog.info("   XAI key：\(grokReady ? "✅ 就緒" : "❌ 缺")")
        AppLog.info("   CEREBRAS key：\(cereReady ? "✅ 就緒" : "❌ 缺")")
        if let llm = cfg.api.llmCorrection, llm.provider != "none", let c = llm.cerebras {
            AppLog.info("   LLM 修正：\(llm.provider)（\(c.model)）")
        } else {
            AppLog.info("   LLM 修正：停用")
        }
        AppLog.info("   詞彙修正：\(cfg.vocab.enabled ? "啟用" : "停用")")
        AppLog.info("   熱鍵：\(cfg.hotkey.recordModifier.uppercased())+\(cfg.hotkey.recordKey) 錄音 / \(cfg.hotkey.modeCycleModifier.uppercased())+\(cfg.hotkey.modeCycleKey) 切模式")
        AppLog.info(String(repeating: "=", count: 50))
    }

    private func fallbackSnapshot() -> SettingsSnapshot {
        let emptyURL = URL(fileURLWithPath: "/dev/null")
        return SettingsSnapshot(
            modes: [], defaultModeId: "pro", currentModeId: "pro",
            rememberLastMode: true, lastModeId: nil,
            vocabEnabled: true, sttKeytermLimit: 10,
            layer1Path: emptyURL, layer2Path: emptyURL, vocabPath: emptyURL,
            loginItemEnabled: false, loginItemStatus: .notRegistered,
            micAuthorized: false, accessibilityTrusted: false,
            hotkey: HotkeyConfig(recordKey: "F1", recordModifier: "ctrl",
                                 modeCycleKey: "F10", modeCycleModifier: "ctrl"),
            sampleRate: 16000, inputDevice: .systemDefault, inputDevices: [],
            xaiSource: SecretSourceInfo(kind: .missing, envFilePath: nil),
            cerebrasSource: SecretSourceInfo(kind: .missing, envFilePath: nil),
            xaiHasKeychainValue: false, cerebrasHasKeychainValue: false,
            llmEnabled: false, llmModel: SettingsLimits.defaultLLMModel,
            llmMaxTokens: 2048, llmReady: false
        )
    }
}
