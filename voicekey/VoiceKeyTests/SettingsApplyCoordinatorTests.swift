import XCTest
@testable import VoiceKey

final class SettingsTestHarness {
    let suiteName = "VoiceKeyTests.Settings.\(UUID().uuidString)"
    let tmpDir: URL
    let writer: ConfigLocalWriter
    let prefs: ModePreferenceStore
    var config: AppConfig
    var busy = false
    var writes = 0
    var runtimeBuilds = 0
    var runtimeSwaps = 0
    var runtimeDiscards = 0
    var hotkeyApplies = 0
    var lastHotkey: HotkeyConfig?
    var rebuildShouldFail = false
    var keychainShouldFail = false
    var keychain: [String: String] = [:]
    var loginEnabled = false
    private(set) var coordinator: SettingsApplyCoordinator!

    init() {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceKeyApply-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let localURL = tmpDir.appendingPathComponent("config.local.json")
        writer = ConfigLocalWriter(localURL: localURL, bundledJSON: ConfigLocalWriterTests.sampleBundled())
        prefs = ModePreferenceStore(suiteName: suiteName)
        prefs.removeAll()
        config = try! ConfigLoader.build(from: ConfigLocalWriterTests.sampleBundled())
        var grok = config.api.grok
        grok.apiKey = "test-not-a-real-key"
        config.api.grok = grok

        let dummyURL = tmpDir.appendingPathComponent("dummy.json")
        coordinator = SettingsApplyCoordinator(env: SettingsEnvironment(
            isBusy: { [weak self] in self?.busy ?? false },
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
                    vocab: VocabConfig(enabled: true, file: "user_vocab.json", sttKeytermLimit: 10,
                                       match: VocabMatchConfig(useTone: false, requireSurnameCharSame: false, minTermLen: 2))
                )
            },
            modes: { [weak self] in self?.config.modes ?? [] },
            currentModeId: { [weak self] in self?.config.modes.first?.id ?? "pro" },
            modePrefs: prefs,
            writer: writer,
            applySecrets: { cfg, _, _ in
                if cfg.api.grok.apiKey.isEmpty { cfg.api.grok.apiKey = "test-not-a-real-key" }
            },
            secretSource: { _, _ in SecretSourceInfo(kind: .missing, envFilePath: nil) },
            keychainHasValue: { [weak self] in self?.keychain[$0] != nil },
            keychainRead: { [weak self] in self?.keychain[$0] },
            keychainReplace: { [weak self] account, value in
                guard let self else { return }
                if self.keychainShouldFail { throw SettingsApplyError.keychainFailed }
                self.keychain[account] = value
            },
            keychainDelete: { [weak self] account in
                guard let self else { return }
                if self.keychainShouldFail { throw SettingsApplyError.keychainFailed }
                self.keychain.removeValue(forKey: account)
            },
            loginStatus: { [weak self] in (self?.loginEnabled ?? false) ? .enabled : .notRegistered },
            setLoginEnabled: { [weak self] on in self?.loginEnabled = on },
            micAuthorized: { false },
            accessibilityTrusted: { false },
            inputDevices: { [AudioInputInfo(name: "Built-in Mic")] },
            vocabPaths: { (dummyURL, dummyURL, dummyURL) },
            applyHotkeys: { [weak self] hk in
                self?.hotkeyApplies += 1
                self?.lastHotkey = hk
            },
            rebuildRuntime: { [weak self] cfg in
                guard let self else { throw ConfigError(message: "harness released") }
                self.runtimeBuilds += 1
                if self.rebuildShouldFail {
                    throw ConfigError(message: "candidate build failed")
                }
                return RuntimeBuild(config: cfg)
            },
            commitRuntime: { [weak self] build in
                self?.runtimeSwaps += 1
                self?.config = build.config
            },
            discardRuntime: { [weak self] _ in
                self?.runtimeDiscards += 1
            },
            replaceConfig: { [weak self] cfg in
                self?.config = cfg
            },
            afterSuccess: { _ in }
        ))
        // Count local writes by wrapping apply/write is hard; inspect file mtime via apply path.
        // Tests that care about writes inspect the local file or use applyRuntime counters.
    }

    deinit {
        prefs.removeAll()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmpDir)
    }

    var localExists: Bool {
        FileManager.default.fileExists(atPath: writer.localURL.path)
    }

    func localJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: writer.localURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError(message: "config.local.json 不是物件")
        }
        return json
    }
}

final class SettingsApplyCoordinatorTests: XCTestCase {
    func testBusyZeroWrites() {
        let h = SettingsTestHarness()
        h.busy = true
        XCTAssertThrowsError(try h.coordinator.apply(.vocabEnabled(false))) { error in
            XCTAssertEqual(error as? SettingsApplyError, .busy)
        }
        XCTAssertFalse(h.localExists)
        XCTAssertEqual(h.runtimeBuilds, 0)
        XCTAssertEqual(h.runtimeSwaps, 0)
        XCTAssertEqual(h.keychain.count, 0)
    }

    func testCandidateBuildFailureKeepsOldRuntime() {
        let h = SettingsTestHarness()
        let oldEnabled = h.config.vocab.enabled
        h.rebuildShouldFail = true
        XCTAssertThrowsError(try h.coordinator.apply(.vocabEnabled(false)))
        XCTAssertEqual(h.runtimeSwaps, 0)
        XCTAssertEqual(h.runtimeDiscards, 0)
        XCTAssertEqual(h.config.vocab.enabled, oldEnabled)
        XCTAssertFalse(h.localExists)
    }

    func testSuccessSwapsOnce() throws {
        let h = SettingsTestHarness()
        try h.coordinator.apply(.vocabEnabled(false))
        XCTAssertEqual(h.runtimeBuilds, 1)
        XCTAssertEqual(h.runtimeSwaps, 1)
        XCTAssertEqual(h.runtimeDiscards, 0)
        XCTAssertFalse(h.config.vocab.enabled)
        let local = try h.localJSON()
        XCTAssertEqual((local["vocab"] as? [String: Any])?["enabled"] as? Bool, false)
        XCTAssertNil(local["modes"])
    }

    func testKeychainFailureRollback() {
        let h = SettingsTestHarness()
        h.keychain["XAI_API_KEY"] = "old-placeholder"
        h.keychainShouldFail = true
        XCTAssertThrowsError(try h.coordinator.apply(
            .apiKeys(xai: .set("new-placeholder"), cerebras: .unchanged)
        ))
        XCTAssertEqual(h.runtimeSwaps, 0)
        XCTAssertEqual(h.runtimeDiscards, 1)
        XCTAssertEqual(h.keychain["XAI_API_KEY"], "old-placeholder")
    }

    func testKeychainSuccessRebuildsRuntime() throws {
        let h = SettingsTestHarness()
        try h.coordinator.apply(.apiKeys(xai: .set("new-placeholder"), cerebras: .unchanged))
        XCTAssertEqual(h.runtimeBuilds, 1)
        XCTAssertEqual(h.runtimeSwaps, 1)
        XCTAssertEqual(h.keychain["XAI_API_KEY"], "new-placeholder")
    }

    func testRememberLastDoesNotRebuild() throws {
        let h = SettingsTestHarness()
        try h.coordinator.apply(.rememberLastMode(true))
        XCTAssertEqual(h.runtimeBuilds, 0)
        XCTAssertEqual(h.runtimeSwaps, 0)
        XCTAssertTrue(h.prefs.rememberLastMode)
        XCTAssertEqual(h.prefs.lastModeId, "pro")
    }

    func testFixedDefaultWritesLocalOnly() throws {
        let h = SettingsTestHarness()
        try h.coordinator.apply(.defaultModeId("casual"))
        XCTAssertEqual(h.runtimeBuilds, 0)
        XCTAssertEqual(h.config.defaultModeId, "casual")
        XCTAssertEqual(try h.localJSON()["default_mode_id"] as? String, "casual")
    }

    func testHotkeyApplyThenWrite() throws {
        let h = SettingsTestHarness()
        try h.coordinator.apply(.hotkeys(recordKey: "F2", recordModifier: "ctrl",
                                         cycleKey: "F9", cycleModifier: "ctrl"))
        XCTAssertEqual(h.hotkeyApplies, 1)
        XCTAssertEqual(h.lastHotkey?.recordKey, "F2")
        XCTAssertEqual(h.runtimeBuilds, 0)
        let hk = try h.localJSON()["hotkey"] as? [String: Any]
        XCTAssertEqual(hk?["record_key"] as? String, "F2")
    }
}
