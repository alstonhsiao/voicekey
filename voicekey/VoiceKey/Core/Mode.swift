import Foundation

/// A single regex correction rule (regex fallback, post-processing).
struct RegexRule {
    let pattern: String
    let replacement: String
    let flags: String
}

/// A transcription mode. Mirrors approach-6 `_voice_config.Mode`.
struct Mode {
    let id: String
    let name: String
    let icon: String
    let language: String
    let translateToEnglish: Bool
    let prompt: String
    let regexRules: [RegexRule]
    /// Base keyterms from config. The effective per-recording list is built by
    /// VocabStores.effectiveKeyterms (vocab/layer1 first, then these) so vocab
    /// hot-reload reaches the STT layer; mutable so VoiceController can swap in
    /// the merged list on its local copy before transcribing.
    var grokKeyterms: [String]
    let llmPrompt: String

    var display: String { "\(icon) \(name)" }

    init?(raw: [String: Any]) {
        guard let id = raw["id"] as? String,
              let name = raw["name"] as? String else {
            return nil
        }
        self.id = id
        self.name = name
        self.icon = raw["icon"] as? String ?? "📝"
        self.language = raw["language"] as? String ?? "zh"
        self.translateToEnglish = raw["translate_to_english"] as? Bool ?? false
        self.prompt = raw["prompt"] as? String ?? ""
        self.llmPrompt = raw["llm_prompt"] as? String ?? ""

        var rules: [RegexRule] = []
        for r in raw["regex_rules"] as? [[String: Any]] ?? [] {
            guard let pattern = r["pattern"] as? String,
                  let replacement = r["replacement"] as? String else { continue }
            rules.append(RegexRule(pattern: pattern,
                                   replacement: replacement,
                                   flags: r["flags"] as? String ?? ""))
        }
        self.regexRules = rules

        var keyterms = (raw["grok_keyterms"] as? [String]) ?? []
        // Backward compat: derive from prompt if no explicit keyterms.
        if keyterms.isEmpty, !prompt.isEmpty {
            keyterms = prompt.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        self.grokKeyterms = keyterms
    }
}

/// Manages switchable transcription modes. Thread-safe (NSLock).
/// Mirrors approach-6 `_voice_config.ModeManager`.
final class ModeManager {
    private var modes: [Mode]
    private var index: Int = 0
    private let lock = NSLock()
    private var listeners: [(Mode) -> Void] = []

    init(modes: [Mode], defaultId: String) {
        precondition(!modes.isEmpty, "config.modes 不可為空")
        self.modes = modes
        if let i = modes.firstIndex(where: { $0.id == defaultId }) {
            self.index = i
        }
    }

    var current: Mode {
        lock.lock(); defer { lock.unlock() }
        return modes[index]
    }

    var all: [Mode] {
        lock.lock(); defer { lock.unlock() }
        return modes
    }

    func setById(_ id: String) {
        lock.lock()
        if let i = modes.firstIndex(where: { $0.id == id }) {
            index = i
        }
        lock.unlock()
        notify()
    }

    func cycle() {
        lock.lock()
        index = (index + 1) % modes.count
        lock.unlock()
        notify()
    }

    func onChange(_ callback: @escaping (Mode) -> Void) {
        listeners.append(callback)
    }

    private func notify() {
        let cur = current
        for cb in listeners {
            cb(cur)
        }
    }
}
