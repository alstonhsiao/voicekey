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

        menu.addItem(actionItem("ℹ️ 關於 VoiceKey（\(Self.versionString)）") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        })

        let quit = NSMenuItem(title: "❌ 結束程式",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
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
