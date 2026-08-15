import Foundation

/// Two-phase write of `config.local.json`: merge typed overrides into the
/// existing local file (never a full bundled dump), validate the effective
/// config, then atomically commit. Callers restore via `LocalConfigCommit.rollback`.
final class ConfigLocalWriter {
    private let lock = NSLock()
    let localURL: URL
    private let bundledProvider: () throws -> [String: Any]

    init(localURL: URL = AppPaths.configLocal,
         bundledJSON: [String: Any]? = nil) {
        self.localURL = localURL
        if let bundledJSON {
            self.bundledProvider = { bundledJSON }
        } else {
            self.bundledProvider = { try ConfigLoader.bundledJSON() }
        }
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Read existing local JSON. Missing file → empty object. Corrupt file → throw.
    func readExistingLocal() throws -> (bytes: Data?, json: [String: Any]) {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return (nil, [:])
        }
        let bytes = try Data(contentsOf: localURL)
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: bytes)
        } catch {
            throw SettingsApplyError.corruptLocal(localURL.path)
        }
        guard let json = obj as? [String: Any] else {
            throw SettingsApplyError.corruptLocal(localURL.path)
        }
        return (bytes, json)
    }

    /// Validate + produce a commit token. Does not write.
    func prepare(_ overrides: [String: Any]) throws -> LocalConfigCommit {
        try withLock {
            try prepareUnlocked(overrides)
        }
    }

    func prepareUnlocked(_ overrides: [String: Any]) throws -> LocalConfigCommit {
        let (previousBytes, existing) = try readExistingLocal()
        let mergedLocal = ConfigLoader.deepMerge(existing, overrides)
        let bundled = try bundledProvider()
        let candidate: AppConfig
        do {
            candidate = try ConfigLoader.effectiveConfig(bundled: bundled, local: mergedLocal)
        } catch {
            throw SettingsApplyError.validation(error.localizedDescription)
        }
        let newBytes = try JSONSerialization.data(
            withJSONObject: mergedLocal,
            options: [.prettyPrinted, .sortedKeys]
        )
        return LocalConfigCommit(
            url: localURL,
            previousBytes: previousBytes,
            newBytes: newBytes,
            candidate: candidate,
            localJSON: mergedLocal
        )
    }

    func write(_ commit: LocalConfigCommit) throws {
        try withLock {
            try commit.write()
        }
    }

    func rollback(_ commit: LocalConfigCommit) throws {
        try withLock {
            try commit.rollback()
        }
    }

    /// Prepare + write in one step. For callers that do not need a mid-flight runtime build.
    @discardableResult
    func apply(_ overrides: [String: Any]) throws -> AppConfig {
        try withLock {
            let commit = try prepareUnlocked(overrides)
            try commit.write()
            return commit.candidate
        }
    }
}

struct LocalConfigCommit {
    let url: URL
    let previousBytes: Data?
    let newBytes: Data
    let candidate: AppConfig
    let localJSON: [String: Any]

    func write() throws {
        do {
            try newBytes.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw SettingsApplyError.writeFailed(error.localizedDescription)
        }
    }

    /// Restore original bytes, or delete the file if it did not exist.
    func rollback() throws {
        if let previousBytes {
            try previousBytes.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
