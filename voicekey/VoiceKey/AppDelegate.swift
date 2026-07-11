import AppKit
import AVFoundation

/// Application lifecycle. Wires together all components.
/// Phase 2: + hotkeys, audio recording, mic permission.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private(set) var config: AppConfig?
    private(set) var modeManager: ModeManager?
    private var voiceController: VoiceController?
    private var hotkeyManager: HotkeyManager?

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
            mm = ModeManager(modes: loaded.modes, defaultId: loaded.defaultModeId)
            transcribe = try TranscribeProviders.build(loaded.api)
            llm = LLMCorrectionProviders.build(loaded.api)
            self.config = cfg
            self.modeManager = mm
            logSummary(cfg, mm)
        } catch {
            AppLog.error("❌ 設定/Provider 初始化失敗：\(error)")
            NSApp.terminate(nil)   // match Python: exit on invalid config
            return
        }

        let sessionLogger = SessionLogger()
        let vc = VoiceController(config: cfg, modeManager: mm,
                                 transcribe: transcribe, llm: llm, vocab: vocab,
                                 sessionLogger: sessionLogger)
        self.voiceController = vc

        let mb = MenuBarController(modeManager: mm, vocab: vocab)
        self.menuBar = mb
        vc.onStateChange = { [weak mb] state in mb?.setState(state) }
        mm.onChange { [weak mb] _ in mb?.refreshModeChecks() }

        logInputDevices(cfg)
        setupHotkeys(cfg)
        requestMicrophoneAccess()
        checkAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SingleInstance.release()
    }

    // MARK: - Hotkeys

    private func setupHotkeys(_ cfg: AppConfig) {        let hk = HotkeyManager()
        var allOK = true
        if let code = KeyCodes.keyCode(for: cfg.hotkey.recordKey) {
            let mods = KeyCodes.modifierFlags(cfg.hotkey.recordModifier)
            allOK = hk.register(keyCode: code, modifiers: mods) { [weak self] in
                self?.voiceController?.toggleRecord()
            } && allOK
        } else {
            AppLog.warn("⚠️ 未知錄音熱鍵：\(cfg.hotkey.recordKey)")
            allOK = false
        }
        if let code = KeyCodes.keyCode(for: cfg.hotkey.modeCycleKey) {
            let mods = KeyCodes.modifierFlags(cfg.hotkey.modeCycleModifier)
            allOK = hk.register(keyCode: code, modifiers: mods) { [weak self] in
                self?.voiceController?.cycleMode()
            } && allOK
        } else {
            AppLog.warn("⚠️ 未知切模式熱鍵：\(cfg.hotkey.modeCycleKey)")
            allOK = false
        }
        self.hotkeyManager = hk
        AppLog.info("⌨️ 熱鍵註冊：\(allOK ? "成功（免「輸入監控」授權）" : "部分失敗（見警告）")")
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

    private func logSummary(_ cfg: AppConfig, _ mm: ModeManager) {        AppLog.info("   模式數：\(mm.all.count)（\(mm.all.map { $0.id }.joined(separator: ", "))）")
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
}
