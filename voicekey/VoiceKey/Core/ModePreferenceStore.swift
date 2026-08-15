import Foundation

/// Persists last-used mode in UserDefaults. Not part of config.local.json.
/// Tests inject an isolated suite so they never touch the real app defaults.
final class ModePreferenceStore {
    static let rememberKey = "VoiceKey.rememberLastMode"
    static let lastModeKey = "VoiceKey.lastModeId"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Isolated suite for tests. Call `tearDown` to remove the domain.
    convenience init(suiteName: String) {
        self.init(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    var rememberLastMode: Bool {
        get {
            if defaults.object(forKey: Self.rememberKey) == nil { return true }
            return defaults.bool(forKey: Self.rememberKey)
        }
        set { defaults.set(newValue, forKey: Self.rememberKey) }
    }

    var lastModeId: String? {
        get {
            guard let id = defaults.string(forKey: Self.lastModeKey), !id.isEmpty else {
                return nil
            }
            return id
        }
        set { defaults.set(newValue, forKey: Self.lastModeKey) }
    }

    /// Startup selection: last (if remembered and still valid) → default → first mode.
    func startupModeId(modes: [Mode], defaultId: String) -> String {
        let ids = modes.map(\.id)
        if rememberLastMode, let last = lastModeId, ids.contains(last) {
            return last
        }
        if ids.contains(defaultId) {
            return defaultId
        }
        let fallback = ids.first ?? defaultId
        AppLog.warn("⚠️ default_mode_id 無效：\(defaultId)，已改用 \(fallback)")
        return fallback
    }

    /// Record a successful mode switch when remember-last is on.
    func noteCurrentMode(_ id: String) {
        guard rememberLastMode else { return }
        lastModeId = id
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.rememberKey)
        defaults.removeObject(forKey: Self.lastModeKey)
    }
}
