import AppKit

/// Retains a closure for NSMenuItem actions (NSMenuItem.target is weak).
final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

/// macOS menu bar status item (NSStatusItem).
/// Phase 6: mode menu (checkmarks) + live state title + 三層詞彙子選單.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let modeManager: ModeManager
    private let vocab: VocabStores
    private var actions: [MenuAction] = []                 // retain action targets
    private var modeItems: [(id: String, item: NSMenuItem)] = []

    init(modeManager: ModeManager, vocab: VocabStores) {
        self.modeManager = modeManager
        self.vocab = vocab
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = Self.title(for: .idle)
        rebuildMenu()
    }

    // MARK: - State

    /// Update the status bar title for the given state (thread-safe → main).
    func setState(_ state: VoiceState) {
        let title = Self.title(for: state)
        if Thread.isMainThread {
            statusItem.button?.title = title
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.button?.title = title
            }
        }
    }

    /// "v0.1.0 build 42" — 讀自 Info.plist（build 號由 package.sh 以 git commit 數注入）。
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) build \(build)"
    }

    private static func title(for state: VoiceState) -> String {
        switch state {
        case .idle:       return "⏸ 待機"
        case .recording:  return "🔴 錄音中"
        case .processing: return "🔄 辨識中"
        case .error:      return "⚠️ 錯誤"
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        actions.removeAll()
        modeItems.removeAll()
        let menu = NSMenu()

        // Mode items (checkmark on current).
        for mode in modeManager.all {
            let id = mode.id
            let item = actionItem(mode.display) { [weak self] in
                self?.modeManager.setById(id)
                AppLog.info("🔀 模式 → \(self?.modeManager.current.display ?? "")")
            }
            item.state = (mode.id == modeManager.current.id) ? .on : .off
            modeItems.append((id: id, item: item))
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(vocabSubmenu("🎙 第一層 — Grok 關鍵詞", "layer1_keyterms.json", vocab.layer1Path))
        menu.addItem(vocabSubmenu("🤖 第二層 — LLM 修正詞", "layer2_corrections.json", vocab.layer2Path))
        menu.addItem(vocabSubmenu("🗂 第三層 — 拼音替換詞", vocab.vocabPath.lastPathComponent, vocab.vocabPath))

        menu.addItem(.separator())

        menu.addItem(actionItem("📦 關於 VoiceKey (\(Self.versionString))") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        })

        let quit = NSMenuItem(title: "❌ 結束程式",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        // macOS 26 的選單版型對「有勾選/子選單的區塊」與純文字區塊縮排不同，
        // title 內嵌 emoji 會導致區塊間對不齊；改走標準 image 欄讓系統統一排版。
        Self.moveLeadingEmojiToImage(in: menu)

        statusItem.menu = menu
    }

    // MARK: - Emoji → image column

    /// 把選單（含子選單）每個項目 title 開頭的 emoji 抽出，改設為 NSMenuItem.image。
    private static func moveLeadingEmojiToImage(in menu: NSMenu) {
        for item in menu.items {
            if let sub = item.submenu { moveLeadingEmojiToImage(in: sub) }
            guard let first = item.title.first, isEmoji(first) else { continue }
            let rest = item.title.dropFirst().drop(while: { $0 == " " })
            item.image = emojiImage(String(first))
            item.title = String(rest)
        }
    }

    private static func isEmoji(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        // 排除數字/ASCII（isEmoji 對 '0'-'9' 也回 true）；FE0F 變體序列一律視為 emoji。
        return scalar.properties.isEmoji && (scalar.value > 0x238C || ch.unicodeScalars.count > 1)
    }

    private static func emojiImage(_ emoji: String) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        let textSize = (emoji as NSString).size(withAttributes: attrs)
        return NSImage(size: NSSize(width: 18, height: 16), flipped: false) { rect in
            (emoji as NSString).draw(
                at: NSPoint(x: (rect.width - textSize.width) / 2,
                            y: (rect.height - textSize.height) / 2),
                withAttributes: attrs)
            return true
        }
    }

    /// Refresh the checkmark on the current mode (call when the mode changes).
    func refreshModeChecks() {
        let apply = { [weak self] in
            guard let self else { return }
            let currentId = self.modeManager.current.id
            for entry in self.modeItems {
                entry.item.state = (entry.id == currentId) ? .on : .off
            }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    private func vocabSubmenu(_ label: String, _ fileName: String, _ path: URL) -> NSMenuItem {
        let parent = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let nameItem = NSMenuItem(title: "📄 \(fileName)", action: nil, keyEquivalent: "")
        nameItem.isEnabled = false
        sub.addItem(nameItem)

        let pathItem = NSMenuItem(title: path.path, action: nil, keyEquivalent: "")
        pathItem.isEnabled = false
        sub.addItem(pathItem)

        sub.addItem(.separator())
        sub.addItem(actionItem("用 VSCode 開啟") {
            Self.open(["-a", "Visual Studio Code", path.path], label: "用 VSCode 開啟")
        })
        sub.addItem(actionItem("用預設 App 開啟") {
            Self.open([path.path], label: "用預設 App 開啟")
        })
        sub.addItem(actionItem("在 Finder 中顯示") {
            Self.open(["-R", path.path], label: "在 Finder 中顯示")
        })

        parent.submenu = sub
        return parent
    }

    private func actionItem(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        return item
    }

    /// Open vocab file via `/usr/bin/open`. Any failure only logs.
    private static func open(_ args: [String], label: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = args
        do {
            try task.run()
            AppLog.info("📂 詞彙檔：\(label)")
        } catch {
            AppLog.warn("⚠️ \(label)失敗（\(error)）")
        }
    }
}
