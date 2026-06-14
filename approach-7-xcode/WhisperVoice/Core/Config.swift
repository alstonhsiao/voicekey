import Foundation

/// Shared filesystem locations.
enum AppPaths {
    /// ~/Library/Application Support/WhisperVoice
    static var appSupport: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Local per-machine override config (not synced).
    static var configLocal: URL {
        appSupport.appendingPathComponent("config.local.json")
    }
}

// MARK: - Config error

struct ConfigError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - Typed config structs

enum InputDeviceSpec {
    case systemDefault
    case index(Int)
    case name(String)
    case candidates([String])

    init(_ raw: Any?) {
        switch raw {
        case let i as Int: self = .index(i)
        case let s as String: self = s.isEmpty ? .systemDefault : .name(s)
        case let arr as [Any]:
            let names = arr.compactMap { $0 as? String }.filter { !$0.isEmpty }
            self = names.isEmpty ? .systemDefault : .candidates(names)
        default: self = .systemDefault
        }
    }
}

struct ProviderEndpoint {
    var apiKey: String
    let model: String
    let endpoint: String
}

struct CerebrasConfig {
    var apiKey: String
    let model: String
    let endpoint: String
    let maxTokens: Int
}

struct LLMCorrectionConfig {
    let provider: String       // "cerebras" / "none"
    var cerebras: CerebrasConfig?
}

struct APIConfig {
    let provider: String       // grok / openai / groq
    let temperature: Double
    var openai: ProviderEndpoint
    var grok: ProviderEndpoint
    var groq: ProviderEndpoint
    var llmCorrection: LLMCorrectionConfig?
}

struct RecordingConfig {
    let sampleRate: Int
    let channels: Int
    let inputDevice: InputDeviceSpec
}

struct HotkeyConfig {
    let recordKey: String
    let recordModifier: String
    let modeCycleKey: String
    let modeCycleModifier: String
}

struct VocabMatchConfig {
    let useTone: Bool
    let requireSurnameCharSame: Bool
    let minTermLen: Int
}

struct VocabConfig {
    let enabled: Bool
    let file: String
    let sttKeytermLimit: Int
    let match: VocabMatchConfig
}

/// Full application configuration.
struct AppConfig {
    var modes: [Mode]
    let defaultModeId: String
    var api: APIConfig
    let recording: RecordingConfig
    let hotkey: HotkeyConfig
    let vocab: VocabConfig
}

// MARK: - Loader

enum ConfigLoader {

    /// Load bundled config.json, deep-merge config.local.json, validate, build typed config.
    static func load() throws -> AppConfig {
        guard let baseURL = Bundle.main.url(forResource: "config", withExtension: "json") else {
            throw ConfigError(message: "找不到 Bundle 內的 config.json")
        }
        let baseData = try Data(contentsOf: baseURL)
        guard var merged = try JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
            throw ConfigError(message: "config.json 不是合法的 JSON 物件")
        }

        // config.local.json overrides (deep merge).
        if let localData = try? Data(contentsOf: AppPaths.configLocal),
           let local = (try? JSONSerialization.jsonObject(with: localData)) as? [String: Any] {
            merged = deepMerge(merged, local)
            AppLog.info("🔧 已套用 config.local.json 覆蓋")
        }

        try validate(merged)
        return try build(from: merged)
    }

    /// Deep merge: dict recurses; arrays/scalars replaced by override.
    static func deepMerge(_ base: [String: Any], _ override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let baseDict = result[key] as? [String: Any],
               let overrideDict = value as? [String: Any] {
                result[key] = deepMerge(baseDict, overrideDict)
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// Schema validation. Mirrors approach-6 `validate_config`.
    static func validate(_ config: [String: Any]) throws {
        guard let modes = config["modes"] as? [Any], !modes.isEmpty else {
            throw ConfigError(message: "config.modes 必須為非空陣列")
        }
        for (i, m) in modes.enumerated() {
            guard let mode = m as? [String: Any] else {
                throw ConfigError(message: "config.modes[\(i)] 必須為物件")
            }
            for field in ["id", "name"] {
                if mode[field] == nil {
                    throw ConfigError(message: "config.modes[\(i)] 缺少必填欄位：\(field)")
                }
            }
        }

        guard let api = config["api"] as? [String: Any] else {
            throw ConfigError(message: "config.api 必須為物件")
        }
        let provider = api["provider"] as? String ?? ""
        guard ["grok", "openai", "groq"].contains(provider) else {
            throw ConfigError(message: "config.api.provider 必須為 grok / openai / groq，目前值：\(provider)")
        }

        let rec = config["recording"] as? [String: Any] ?? [:]
        guard rec["sample_rate"] is Int else {
            throw ConfigError(message: "config.recording.sample_rate 必須為整數")
        }
        guard rec["channels"] is Int else {
            throw ConfigError(message: "config.recording.channels 必須為整數")
        }
        let dev = rec["input_device"]
        if dev != nil, !(dev is Int || dev is String || dev is [Any] || dev is NSNull) {
            throw ConfigError(message: "config.recording.input_device 必須為字串、整數、陣列或 null")
        }
    }

    private static func build(from c: [String: Any]) throws -> AppConfig {
        // modes
        let rawModes = c["modes"] as? [[String: Any]] ?? []
        let modes = rawModes.compactMap { Mode(raw: $0) }
        guard !modes.isEmpty else { throw ConfigError(message: "config.modes 解析後為空") }

        // api
        let api = c["api"] as? [String: Any] ?? [:]
        let temperature = (api["temperature"] as? NSNumber)?.doubleValue ?? 0.0
        func endpoint(_ name: String, defaultEndpoint: String, defaultModel: String) -> ProviderEndpoint {
            let sub = api[name] as? [String: Any] ?? [:]
            return ProviderEndpoint(
                apiKey: sub["api_key"] as? String ?? "",
                model: sub["model"] as? String ?? defaultModel,
                endpoint: sub["endpoint"] as? String ?? defaultEndpoint
            )
        }
        var llm: LLMCorrectionConfig?
        if let llmRaw = api["llm_correction"] as? [String: Any] {
            let provName = (llmRaw["provider"] as? String ?? "none").lowercased()
            var cere: CerebrasConfig?
            if let cRaw = llmRaw["cerebras"] as? [String: Any] {
                cere = CerebrasConfig(
                    apiKey: cRaw["api_key"] as? String ?? "",
                    model: cRaw["model"] as? String ?? "llama3.3-70b",
                    endpoint: cRaw["endpoint"] as? String ?? "https://api.cerebras.ai/v1/chat/completions",
                    maxTokens: (cRaw["max_tokens"] as? NSNumber)?.intValue ?? 512
                )
            }
            llm = LLMCorrectionConfig(provider: provName, cerebras: cere)
        }
        let apiConfig = APIConfig(
            provider: (api["provider"] as? String ?? "grok").lowercased(),
            temperature: temperature,
            openai: endpoint("openai", defaultEndpoint: "https://api.openai.com/v1/audio/transcriptions", defaultModel: "gpt-4o-transcribe"),
            grok: endpoint("grok", defaultEndpoint: "https://api.x.ai/v1/stt", defaultModel: "grok-stt"),
            groq: endpoint("groq", defaultEndpoint: "https://api.groq.com/openai/v1/audio/transcriptions", defaultModel: "whisper-large-v3-turbo"),
            llmCorrection: llm
        )

        // recording
        let rec = c["recording"] as? [String: Any] ?? [:]
        let recording = RecordingConfig(
            sampleRate: rec["sample_rate"] as? Int ?? 16000,
            channels: rec["channels"] as? Int ?? 1,
            inputDevice: InputDeviceSpec(rec["input_device"])
        )

        // hotkey
        let hk = c["hotkey"] as? [String: Any] ?? [:]
        let hotkey = HotkeyConfig(
            recordKey: hk["record_key"] as? String ?? "F1",
            recordModifier: (hk["record_modifier"] as? String ?? "ctrl").lowercased(),
            modeCycleKey: hk["mode_cycle_key"] as? String ?? "F10",
            modeCycleModifier: (hk["mode_cycle_modifier"] as? String ?? "ctrl").lowercased()
        )

        // vocab
        let v = c["vocab"] as? [String: Any] ?? [:]
        let match = v["match"] as? [String: Any] ?? [:]
        let vocab = VocabConfig(
            enabled: v["enabled"] as? Bool ?? false,
            file: v["file"] as? String ?? "user_vocab.json",
            sttKeytermLimit: v["stt_keyterm_limit"] as? Int ?? 10,
            match: VocabMatchConfig(
                useTone: match["use_tone"] as? Bool ?? false,
                requireSurnameCharSame: match["require_surname_char_same"] as? Bool ?? false,
                minTermLen: match["min_term_len"] as? Int ?? 2
            )
        )

        return AppConfig(
            modes: modes,
            defaultModeId: c["default_mode_id"] as? String ?? "direct",
            api: apiConfig,
            recording: recording,
            hotkey: hotkey,
            vocab: vocab
        )
    }
}
