import Foundation

/// Resolves API keys. Priority (mirrors approach-6 README):
/// 1. Environment variables
/// 2. env.local / .env.local (App Support dir, or path from VOICEKEY_ENV_FILE)
/// 3. Keychain (kSecClassGenericPassword) — for .app distribution
/// 4. config.json api_key field (already in AppConfig; left untouched if nothing better)
///
/// ⚠️ Keys are never written to git or bundled into Resources.
/// ⚠️ Never log key values (full or partial).
enum SecretSource: String, Equatable {
    case processEnvironment
    case envFile
    case keychain
    case config
    case missing
}

struct SecretSourceInfo: Equatable {
    let kind: SecretSource
    /// Path of the env.local file if that layer supplied the value. Never the contents.
    let envFilePath: String?

    var usesHigherPriorityThanKeychain: Bool {
        kind == .processEnvironment || kind == .envFile
    }

    var displayName: String {
        switch kind {
        case .processEnvironment: return "Process Environment"
        case .envFile: return "env.local"
        case .keychain: return "Keychain"
        case .config: return "bundled config"
        case .missing: return "missing"
        }
    }
}

enum APIKeyEdit: Equatable {
    case unchanged
    case set(String)
    case clear
}

enum Secrets {
    static let defaultService = "com.alston.VoiceKey"
    /// Pre-rename service name; read-only fallback so stored keys keep working.
    static let legacyService = "com.alston.WhisperVoice"
    /// Tests override this so they never touch the production Keychain items.
    static var keychainServiceName = defaultService

    struct EnvResolution {
        let process: [String: String]
        let file: [String: String]
        let fileURL: URL?
    }

    /// Inject resolved keys into the config.
    static func apply(to config: inout AppConfig,
                      xaiEdit: APIKeyEdit = .unchanged,
                      cerebrasEdit: APIKeyEdit = .unchanged,
                      openaiEdit: APIKeyEdit = .unchanged,
                      groqEdit: APIKeyEdit = .unchanged) {
        func resolve(_ envName: String, current: String, edit: APIKeyEdit) -> String {
            resolvedValue(account: envName, configValue: current, edit: edit)
        }

        config.api.openai.apiKey = resolve("OPENAI_API_KEY", current: config.api.openai.apiKey, edit: openaiEdit)
        config.api.grok.apiKey   = resolve("XAI_API_KEY",    current: config.api.grok.apiKey, edit: xaiEdit)
        config.api.groq.apiKey   = resolve("GROQ_API_KEY",   current: config.api.groq.apiKey, edit: groqEdit)
        if config.api.llmCorrection?.cerebras != nil {
            let cur = config.api.llmCorrection!.cerebras!.apiKey
            config.api.llmCorrection!.cerebras!.apiKey = resolve("CEREBRAS_API_KEY", current: cur, edit: cerebrasEdit)
        }
    }

    static func resolvedValue(account: String, configValue: String, edit: APIKeyEdit = .unchanged) -> String {
        let env = resolveEnv()
        if let v = env.process[account], !v.isEmpty { return v }
        if let v = env.file[account], !v.isEmpty { return v }
        switch edit {
        case .unchanged:
            if let v = keychainRead(account: account), !v.isEmpty { return v }
            return configValue
        case .set(let v):
            return v
        case .clear:
            return configValue
        }
    }

    static func source(for account: String, configValue: String = "") -> SecretSourceInfo {
        let env = resolveEnv()
        if let v = env.process[account], !v.isEmpty {
            return SecretSourceInfo(kind: .processEnvironment, envFilePath: nil)
        }
        if let v = env.file[account], !v.isEmpty {
            return SecretSourceInfo(kind: .envFile, envFilePath: env.fileURL?.path)
        }
        if let v = keychainRead(account: account), !v.isEmpty {
            return SecretSourceInfo(kind: .keychain, envFilePath: env.fileURL?.path)
        }
        if !configValue.isEmpty {
            return SecretSourceInfo(kind: .config, envFilePath: env.fileURL?.path)
        }
        return SecretSourceInfo(kind: .missing, envFilePath: env.fileURL?.path)
    }

    /// Merge ProcessInfo env vars (highest) + first found env.local file.
    /// Env vars win over file values (matches os.environ.setdefault semantics).
    static func loadEnv() -> [String: String] {
        let r = resolveEnv()
        var merged = r.process
        for (k, v) in r.file where merged[k] == nil {
            merged[k] = v
        }
        return merged
    }

    static func resolveEnv() -> EnvResolution {
        let process = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let custom = process["VOICEKEY_ENV_FILE"] ?? process["WHISPERVOICE_ENV_FILE"], !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: custom))
        }
        candidates.append(AppPaths.appSupport.appendingPathComponent("env.local"))
        candidates.append(AppPaths.appSupport.appendingPathComponent(".env.local"))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("env.local"))

        for url in candidates {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var file: [String: String] = [:]
            for rawLine in content.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                      let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if file[key] == nil {
                    file[key] = value
                }
            }
            return EnvResolution(process: process, file: file, fileURL: url)
        }
        return EnvResolution(process: process, file: [:], fileURL: nil)
    }

    // MARK: - Keychain

    static func keychainHasValue(account: String) -> Bool {
        guard let v = keychainRead(account: account) else { return false }
        return !v.isEmpty
    }

    static func keychainRead(account: String) -> String? {
        keychainRead(service: keychainServiceName, account: account)
            ?? (keychainServiceName == defaultService
                ? keychainRead(service: legacyService, account: account)
                : nil)
    }

    private static func keychainRead(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Replace an item. Empty values are rejected — use `keychainDelete` to clear.
    @discardableResult
    static func keychainReplace(account: String, value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    /// Kept for existing call sites; same as replace.
    @discardableResult
    static func keychainWrite(account: String, value: String) -> Bool {
        keychainReplace(account: account, value: value)
    }

    /// Delete the current-service item. Also removes the legacy item so a
    /// Settings "clear" is not shadowed by the pre-rename Keychain entry.
    @discardableResult
    static func keychainDelete(account: String) -> Bool {
        var ok = delete(service: keychainServiceName, account: account)
        if keychainServiceName == defaultService {
            let legacy = delete(service: legacyService, account: account)
            ok = ok || legacy
        }
        return ok
    }

    private static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
