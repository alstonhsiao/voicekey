import Foundation

/// Resolves API keys. Priority (mirrors approach-6 README):
/// 1. Environment variables
/// 2. env.local / .env.local (App Support dir, or path from WHISPERVOICE_ENV_FILE)
/// 3. Keychain (kSecClassGenericPassword) — for .app distribution
/// 4. config.json api_key field (already in AppConfig; left untouched if nothing better)
///
/// ⚠️ Keys are never written to git or bundled into Resources.
enum Secrets {

    /// Inject resolved keys into the config.
    static func apply(to config: inout AppConfig) {
        let env = loadEnv()

        func resolve(_ envName: String, current: String) -> String {
            if let v = env[envName], !v.isEmpty { return v }
            if let v = keychainRead(account: envName), !v.isEmpty { return v }
            return current
        }

        config.api.openai.apiKey = resolve("OPENAI_API_KEY", current: config.api.openai.apiKey)
        config.api.grok.apiKey   = resolve("XAI_API_KEY",    current: config.api.grok.apiKey)
        config.api.groq.apiKey   = resolve("GROQ_API_KEY",   current: config.api.groq.apiKey)
        if config.api.llmCorrection?.cerebras != nil {
            let cur = config.api.llmCorrection!.cerebras!.apiKey
            config.api.llmCorrection!.cerebras!.apiKey = resolve("CEREBRAS_API_KEY", current: cur)
        }
    }

    /// Merge ProcessInfo env vars (highest) + first found env.local file.
    /// Env vars win over file values (matches os.environ.setdefault semantics).
    static func loadEnv() -> [String: String] {
        var result = ProcessInfo.processInfo.environment

        var candidates: [URL] = []
        if let custom = result["WHISPERVOICE_ENV_FILE"], !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: custom))
        }
        candidates.append(AppPaths.appSupport.appendingPathComponent("env.local"))
        candidates.append(AppPaths.appSupport.appendingPathComponent(".env.local"))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("env.local"))

        for url in candidates {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for rawLine in content.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                      let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if result[key] == nil {   // setdefault: env vars win
                    result[key] = value
                }
            }
            break   // first found file only
        }
        return result
    }

    // MARK: - Keychain

    private static let keychainService = "com.alston.WhisperVoice"

    static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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

    @discardableResult
    static func keychainWrite(account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
