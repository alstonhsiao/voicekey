import Foundation

// MARK: - CJK helpers (matches approach-6 _is_cjk / _all_cjk, U+3400…U+9FFF)

private func isCJK(_ ch: Character) -> Bool {
    let scalars = ch.unicodeScalars
    guard scalars.count == 1, let v = scalars.first?.value else { return false }
    return v >= 0x3400 && v <= 0x9FFF
}

private func allCJK(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy(isCJK)
}

private struct PinyinKey: Hashable {
    let len: Int
    let syllables: [String]
}

// MARK: - Layer 3: pinyin fuzzy + overrides + STT keyterms

/// Third post-processing layer: user vocab pinyin fuzzy replacement.
/// Runs after LLM correction, before paste. Never throws — degrades to original.
/// Mirrors approach-6 `_voice_vocab.VocabStore`.
final class VocabStore {
    private static let pinyinCategories = ["people", "companies", "projects"]
    private static let keytermCategories = ["people", "companies", "projects", "terms"]

    private let path: URL
    private let requireSurnameCharSame: Bool
    private let minTermLen: Int

    private var mtime: Date?
    private var pinyinIndex: [PinyinKey: String] = [:]
    private var lengths: [Int] = []          // descending
    private var overrides: [String: String] = [:]
    private var keyterms: [String] = []

    init(path: URL, match: VocabMatchConfig) {
        self.path = path
        self.requireSurnameCharSame = match.requireSurnameCharSame
        self.minTermLen = match.minTermLen
        maybeReload(force: true)
    }

    var sttKeyterms: [String] { keyterms }

    // MARK: load / index

    func maybeReload(force: Bool = false) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modified = attrs[.modificationDate] as? Date else {
            return  // file missing — keep previous data
        }
        if !force, modified == mtime { return }
        guard let data = try? Data(contentsOf: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            AppLog.warn("⚠️ user_vocab.json 載入失敗，沿用上一版")
            return
        }
        rebuild(json)
        mtime = modified
    }

    private func rebuild(_ data: [String: Any]) {
        var index: [PinyinKey: String] = [:]
        var lengthSet = Set<Int>()
        for cat in Self.pinyinCategories {
            for raw in (data[cat] as? [Any]) ?? [] {
                guard let s = raw as? String else { continue }
                let term = s.trimmingCharacters(in: .whitespaces)
                guard term.count >= minTermLen, allCJK(term) else { continue }
                let key = PinyinKey(len: term.count, syllables: PinyinEngine.syllables(term))
                if let existing = index[key], existing != term {
                    AppLog.warn("⚠️ 詞彙拼音衝突：\(existing) 與 \(term) 同音同字數，保留前者")
                    continue
                }
                index[key] = term
                lengthSet.insert(term.count)
            }
        }

        var ov: [String: String] = [:]
        if let rawOv = data["overrides"] as? [String: Any] {
            for (k, v) in rawOv {
                guard k != "_comment", let value = v as? String, !k.isEmpty, !value.isEmpty else { continue }
                ov[k] = value
            }
        }

        var seen = Set<String>()
        var terms: [String] = []
        for cat in Self.keytermCategories {
            for raw in (data[cat] as? [Any]) ?? [] {
                guard let s = raw as? String else { continue }
                let t = s.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, !seen.contains(t) { seen.insert(t); terms.append(t) }
            }
        }

        pinyinIndex = index
        lengths = lengthSet.sorted(by: >)
        overrides = ov
        keyterms = terms
    }

    // MARK: apply

    /// Layer-3 entry: literal overrides first, then pinyin fuzzy. Never throws.
    func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for (wrong, right) in overrides where result.contains(wrong) {
            result = result.replacingOccurrences(of: wrong, with: right)
        }
        if !pinyinIndex.isEmpty {
            result = applyPinyin(result)
        }
        return result
    }

    private func applyPinyin(_ text: String) -> String {
        let chars = Array(text)
        let n = chars.count
        guard n > 0 else { return text }
        var claimed = [Bool](repeating: false, count: n)
        var replacements: [(Int, Int, String)] = []

        for L in lengths {
            if L > n { continue }
            for i in 0...(n - L) {
                let window = String(chars[i..<(i + L)])
                guard allCJK(window) else { continue }
                let key = PinyinKey(len: L, syllables: PinyinEngine.syllables(window))
                guard let canonical = pinyinIndex[key], window != canonical else { continue }
                if requireSurnameCharSame, window.first != canonical.first { continue }
                if (i..<(i + L)).contains(where: { claimed[$0] }) { continue }
                for j in i..<(i + L) { claimed[j] = true }
                replacements.append((i, i + L, canonical))
            }
        }

        guard !replacements.isEmpty else { return text }
        var result = chars
        for (start, end, canonical) in replacements.sorted(by: { $0.0 > $1.0 }) {
            result.replaceSubrange(start..<end, with: Array(canonical))
        }
        return String(result)
    }
}

// MARK: - Layer 1: Grok STT keyterms

/// First layer: extra Grok STT keyterms (hot-reload via mtime).
final class Layer1VocabStore {
    private let path: URL
    private var mtime: Date?
    private(set) var keyterms: [String] = []

    init(path: URL) {
        self.path = path
        maybeReload(force: true)
    }

    func maybeReload(force: Bool = false) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modified = attrs[.modificationDate] as? Date else { return }
        if !force, modified == mtime { return }
        guard let data = try? Data(contentsOf: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            AppLog.warn("⚠️ layer1_keyterms.json 載入失敗，沿用上一版")
            return
        }
        keyterms = ((json["keyterms"] as? [Any]) ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        mtime = modified
    }
}

// MARK: - Layer 2: Cerebras LLM correction vocab

/// Second layer: LLM correction names + corrections (hot-reload via mtime).
final class Layer2VocabStore {
    private let path: URL
    private var mtime: Date?
    private(set) var names: [String] = []
    private(set) var corrections: [(String, String)] = []   // ordered for determinism

    init(path: URL) {
        self.path = path
        maybeReload(force: true)
    }

    func maybeReload(force: Bool = false) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modified = attrs[.modificationDate] as? Date else { return }
        if !force, modified == mtime { return }
        guard let data = try? Data(contentsOf: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            AppLog.warn("⚠️ layer2_corrections.json 載入失敗，沿用上一版")
            return
        }
        names = ((json["names"] as? [Any]) ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var corr: [(String, String)] = []
        if let rawCorr = json["corrections"] as? [String: Any] {
            for (k, v) in rawCorr.sorted(by: { $0.key < $1.key }) {
                guard k != "_comment", let value = v as? String, !k.isEmpty, !value.isEmpty else { continue }
                corr.append((k, value))
            }
        }
        corrections = corr
        mtime = modified
    }

    /// Dynamic injection appended to the LLM system prompt. Empty file → "".
    func buildInjection() -> String {
        if names.isEmpty && corrections.isEmpty { return "" }
        var parts: [String] = []
        if !names.isEmpty {
            parts.append("以下人名與術語請正確拼寫：" + names.joined(separator: "、"))
        }
        if !corrections.isEmpty {
            let corrStr = corrections.map { "\($0.0)→\($0.1)" }.joined(separator: "、")
            parts.append("以下詞語請強制替換：" + corrStr)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Container

/// Holds all three vocab layers + their (user-writable) file paths.
/// Files live in ~/Library/Application Support/VoiceKey (seeded from bundle).
final class VocabStores {
    let layer3: VocabStore?
    let layer1: Layer1VocabStore
    let layer2: Layer2VocabStore
    let vocabPath: URL
    let layer1Path: URL
    let layer2Path: URL

    init(config: AppConfig) {
        let dir = AppPaths.appSupport
        Self.seedIfNeeded(dir)
        vocabPath = dir.appendingPathComponent(config.vocab.file)
        layer1Path = dir.appendingPathComponent("layer1_keyterms.json")
        layer2Path = dir.appendingPathComponent("layer2_corrections.json")
        layer1 = Layer1VocabStore(path: layer1Path)
        layer2 = Layer2VocabStore(path: layer2Path)
        if config.vocab.enabled {
            layer3 = VocabStore(path: vocabPath, match: config.vocab.match)
            AppLog.info("🗂 第三層詞彙：\(layer3?.sttKeyterms.count ?? 0) 詞")
        } else {
            layer3 = nil
            AppLog.info("ℹ️ 詞彙修正：停用（vocab.enabled=false）")
        }
    }

    /// Hot-reload all layers (called at record start, matching approach-6).
    func maybeReloadAll() {
        layer3?.maybeReload()
        layer1.maybeReload()
        layer2.maybeReload()
    }

    /// Seed user-writable vocab files from bundle defaults on first launch.
    private static func seedIfNeeded(_ dir: URL) {
        for name in ["user_vocab", "layer1_keyterms", "layer2_corrections"] {
            let dest = dir.appendingPathComponent("\(name).json")
            guard !FileManager.default.fileExists(atPath: dest.path),
                  let src = Bundle.main.url(forResource: name, withExtension: "json") else { continue }
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                AppLog.info("📄 已建立詞彙檔：\(dest.path)")
            } catch {
                AppLog.warn("⚠️ 無法建立詞彙檔 \(dest.lastPathComponent)：\(error)")
            }
        }
    }

    /// Effective STT keyterms for one recording.
    /// Computed per recording (after maybeReloadAll) so vocab-file hot-reload
    /// actually reaches the STT layer. User-editable files (layer3 + layer1)
    /// come before the mode's static config keyterms so they are never crowded
    /// out by a full static list once the limit truncates.
    func effectiveKeyterms(for mode: Mode, limit: Int) -> [String] {
        Self.mergeKeyterms(vocabTerms: layer3?.sttKeyterms ?? [],
                           layer1Terms: layer1.keyterms,
                           modeTerms: mode.grokKeyterms,
                           limit: limit)
    }

    static func mergeKeyterms(vocabTerms: [String], layer1Terms: [String],
                              modeTerms: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for kw in vocabTerms + layer1Terms + modeTerms where !kw.isEmpty && !seen.contains(kw) {
            seen.insert(kw)
            merged.append(kw)
        }
        return Array(merged.prefix(limit))
    }
}
