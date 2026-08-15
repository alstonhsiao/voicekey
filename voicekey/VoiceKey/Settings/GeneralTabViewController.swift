import AppKit

final class GeneralTabViewController: SettingsTabViewController {
    private let rememberBox = NSButton(checkboxWithTitle: "記住上次使用模式", target: nil, action: nil)
    private let defaultPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let defaultHelp = SettingsTabViewController.help("找不到上次模式時使用此值")
    private let loginBox = NSButton(checkboxWithTitle: "登入時自動啟動", target: nil, action: nil)
    private let loginStatus = SettingsTabViewController.help("")
    private let loginOpen = NSButton(title: "打開登入項目設定", target: nil, action: nil)
    private let vocabBox = NSButton(checkboxWithTitle: "詞彙修正", target: nil, action: nil)
    private let keytermStepper = NSStepper()
    private let keytermField = NSTextField(labelWithString: "10")
    private let micStatus = SettingsTabViewController.help("")
    private let axStatus = SettingsTabViewController.help("")
    private var isRefreshing = false

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 460))
        self.view = view
        let stack = Self.stack(in: view)

        rememberBox.target = self
        rememberBox.action = #selector(rememberChanged)
        defaultPopup.target = self
        defaultPopup.action = #selector(defaultModeChanged)
        loginBox.target = self
        loginBox.action = #selector(loginChanged)
        loginOpen.target = self
        loginOpen.action = #selector(openLoginSettings)
        vocabBox.target = self
        vocabBox.action = #selector(vocabChanged)
        keytermStepper.minValue = Double(SettingsLimits.keytermMin)
        keytermStepper.maxValue = Double(SettingsLimits.keytermMax)
        keytermStepper.increment = 1
        keytermStepper.valueWraps = false
        keytermStepper.target = self
        keytermStepper.action = #selector(keytermChanged)

        stack.addArrangedSubview(Self.heading("啟動模式"))
        stack.addArrangedSubview(rememberBox)
        stack.addArrangedSubview(Self.labeledRow("固定預設模式", defaultPopup))
        stack.addArrangedSubview(defaultHelp)

        stack.addArrangedSubview(Self.heading("開機"))
        stack.addArrangedSubview(loginBox)
        stack.addArrangedSubview(loginStatus)
        stack.addArrangedSubview(loginOpen)

        stack.addArrangedSubview(Self.heading("詞彙"))
        stack.addArrangedSubview(vocabBox)
        let keytermRow = NSStackView(views: [
            NSTextField(labelWithString: "STT 關鍵詞上限"),
            keytermField,
            keytermStepper,
        ])
        keytermRow.orientation = .horizontal
        keytermRow.alignment = .centerY
        keytermRow.spacing = 8
        stack.addArrangedSubview(keytermRow)
        stack.addArrangedSubview(Self.help("範圍 0–10（與目前 Grok STT 上限一致）"))

        stack.addArrangedSubview(Self.heading("詞彙檔"))
        stack.addArrangedSubview(fileRow("第一層", #selector(openLayer1)))
        stack.addArrangedSubview(fileRow("第二層", #selector(openLayer2)))
        stack.addArrangedSubview(fileRow("第三層", #selector(openLayer3)))

        stack.addArrangedSubview(Self.heading("權限"))
        stack.addArrangedSubview(statusRow(micStatus, title: "打開麥克風設定", action: #selector(openMic)))
        stack.addArrangedSubview(statusRow(axStatus, title: "打開輔助使用設定", action: #selector(openAX)))
    }

    override func refresh() {
        isRefreshing = true
        rememberBox.state = snapshot.rememberLastMode ? .on : .off
        defaultPopup.removeAllItems()
        for mode in snapshot.modes {
            defaultPopup.addItem(withTitle: mode.display)
            defaultPopup.lastItem?.representedObject = mode.id
        }
        if let idx = snapshot.modes.firstIndex(where: { $0.id == snapshot.defaultModeId }) {
            defaultPopup.selectItem(at: idx)
        }
        defaultHelp.stringValue = snapshot.rememberLastMode
            ? "找不到上次模式時使用此值"
            : "下次啟動時使用此模式"
        loginBox.state = snapshot.loginItemEnabled ? .on : .off
        loginStatus.stringValue = "狀態：\(snapshot.loginItemStatus.displayText)"
        loginOpen.isHidden = snapshot.loginItemStatus != .requiresApproval
            && snapshot.loginItemStatus != .notFound
        vocabBox.state = snapshot.vocabEnabled ? .on : .off
        keytermStepper.integerValue = snapshot.sttKeytermLimit
        keytermField.stringValue = "\(snapshot.sttKeytermLimit)"
        micStatus.stringValue = "麥克風：" + (snapshot.micAuthorized ? "已授權" : "未授權")
        axStatus.stringValue = "輔助使用：" + (snapshot.accessibilityTrusted ? "已授權" : "未授權")
        isRefreshing = false
    }

    private func fileRow(_ title: String, _ action: Selector) -> NSStackView {
        let open = NSButton(title: "用預設 App 開啟", target: self, action: action)
        let revealSel: Selector
        switch action {
        case #selector(openLayer1): revealSel = #selector(revealLayer1)
        case #selector(openLayer2): revealSel = #selector(revealLayer2)
        default: revealSel = #selector(revealLayer3)
        }
        let reveal = NSButton(title: "在 Finder 顯示", target: self, action: revealSel)
        return Self.labeledRow(title, NSStackView(views: [open, reveal]))
    }

    private func statusRow(_ label: NSTextField, title: String, action: Selector) -> NSStackView {
        let btn = NSButton(title: title, target: self, action: action)
        let row = NSStackView(views: [label, btn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc private func rememberChanged() {
        guard !isRefreshing else { return }
        apply(.rememberLastMode(rememberBox.state == .on))
    }

    @objc private func defaultModeChanged() {
        guard !isRefreshing else { return }
        guard let id = defaultPopup.selectedItem?.representedObject as? String else { return }
        apply(.defaultModeId(id))
    }

    @objc private func loginChanged() {
        guard !isRefreshing else { return }
        apply(.loginItem(loginBox.state == .on))
    }

    @objc private func vocabChanged() {
        guard !isRefreshing else { return }
        apply(.vocabEnabled(vocabBox.state == .on))
    }

    @objc private func keytermChanged() {
        guard !isRefreshing else { return }
        apply(.sttKeytermLimit(keytermStepper.integerValue))
    }

    @objc private func openLoginSettings() { SystemSettingsOpener.openLoginItems() }
    @objc private func openMic() { SystemSettingsOpener.openMicrophone() }
    @objc private func openAX() { SystemSettingsOpener.openAccessibility() }

    @objc private func openLayer1() { VocabFileActions.openInDefaultApp(snapshot.layer1Path) }
    @objc private func openLayer2() { VocabFileActions.openInDefaultApp(snapshot.layer2Path) }
    @objc private func openLayer3() { VocabFileActions.openInDefaultApp(snapshot.vocabPath) }
    @objc private func revealLayer1() { VocabFileActions.revealInFinder(snapshot.layer1Path) }
    @objc private func revealLayer2() { VocabFileActions.revealInFinder(snapshot.layer2Path) }
    @objc private func revealLayer3() { VocabFileActions.revealInFinder(snapshot.vocabPath) }
}
