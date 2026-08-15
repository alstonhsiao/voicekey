import AppKit

final class HotkeyTabViewController: SettingsTabViewController {
    private var recordField: HotkeyRecorderField!
    private var cycleField: HotkeyRecorderField!
    private let statusLabel = SettingsTabViewController.help("")
    private let applyButton = NSButton(title: "套用熱鍵", target: nil, action: nil)

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 280))
        self.view = view
        let stack = Self.stack(in: view)

        recordField = HotkeyRecorderField(key: snapshot.hotkey.recordKey,
                                          modifier: snapshot.hotkey.recordModifier)
        cycleField = HotkeyRecorderField(key: snapshot.hotkey.modeCycleKey,
                                         modifier: snapshot.hotkey.modeCycleModifier)
        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        applyButton.keyEquivalent = "\r"

        stack.addArrangedSubview(Self.heading("全域熱鍵"))
        stack.addArrangedSubview(Self.help("只接受修飾鍵 + F1–F20。兩個功能不可使用相同組合。點欄位後按下新熱鍵。"))
        stack.addArrangedSubview(Self.labeledRow("錄音", recordField))
        stack.addArrangedSubview(Self.labeledRow("切換模式", cycleField))
        stack.addArrangedSubview(applyButton)
        stack.addArrangedSubview(statusLabel)
    }

    override func refresh() {
        guard isViewLoaded, recordField != nil, cycleField != nil else { return }
        recordField.setCombo(key: snapshot.hotkey.recordKey, modifier: snapshot.hotkey.recordModifier)
        cycleField.setCombo(key: snapshot.hotkey.modeCycleKey, modifier: snapshot.hotkey.modeCycleModifier)
        statusLabel.stringValue = "目前：\(KeyCodes.displayString(key: snapshot.hotkey.recordKey, modifier: snapshot.hotkey.recordModifier)) 錄音　\(KeyCodes.displayString(key: snapshot.hotkey.modeCycleKey, modifier: snapshot.hotkey.modeCycleModifier)) 切換模式"
    }

    @objc private func applyTapped() {
        apply(.hotkeys(recordKey: recordField.keyName,
                       recordModifier: recordField.modifierName,
                       cycleKey: cycleField.keyName,
                       cycleModifier: cycleField.modifierName))
    }
}
