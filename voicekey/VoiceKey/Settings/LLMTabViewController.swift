import AppKit

final class LLMTabViewController: SettingsTabViewController {
    private let enableBox = NSButton(checkboxWithTitle: "啟用 LLM 修正（Cerebras）", target: nil, action: nil)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customField = NSTextField(string: "")
    private let tokensStepper = NSStepper()
    private let tokensField = NSTextField(labelWithString: "2048")
    private let readyLabel = SettingsTabViewController.help("")
    private let applyButton = NSButton(title: "套用 LLM 設定", target: nil, action: nil)
    private var isRefreshing = false

    private static let presetModel = SettingsLimits.defaultLLMModel
    private static let customTitle = "自訂…"

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        self.view = view
        let stack = Self.stack(in: view)

        enableBox.target = self
        modelPopup.target = self
        modelPopup.action = #selector(modelPopupChanged)
        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        tokensStepper.minValue = Double(SettingsLimits.maxTokensMin)
        tokensStepper.maxValue = Double(SettingsLimits.maxTokensMax)
        tokensStepper.increment = 256
        tokensStepper.valueWraps = false
        tokensStepper.target = self
        tokensStepper.action = #selector(tokensStepped)
        customField.placeholderString = "自訂模型名稱"
        customField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: Self.presetModel)
        modelPopup.addItem(withTitle: Self.customTitle)

        stack.addArrangedSubview(Self.heading("LLM 修正"))
        stack.addArrangedSubview(enableBox)
        stack.addArrangedSubview(readyLabel)
        stack.addArrangedSubview(Self.labeledRow("模型", modelPopup))
        stack.addArrangedSubview(Self.labeledRow("自訂模型", customField))
        let tokenRow = NSStackView(views: [
            NSTextField(labelWithString: "Max tokens"),
            tokensField,
            tokensStepper,
        ])
        tokenRow.orientation = .horizontal
        tokenRow.alignment = .centerY
        tokenRow.spacing = 8
        stack.addArrangedSubview(tokenRow)
        stack.addArrangedSubview(Self.help("範圍 \(SettingsLimits.maxTokensMin)–\(SettingsLimits.maxTokensMax)。沒有 Cerebras 金鑰時仍可儲存；辨識失敗會沿用原始 STT，不會崩潰。"))
        stack.addArrangedSubview(applyButton)
    }

    override func refresh() {
        isRefreshing = true
        enableBox.state = snapshot.llmEnabled ? .on : .off
        if snapshot.llmModel == Self.presetModel {
            modelPopup.selectItem(withTitle: Self.presetModel)
            customField.stringValue = ""
            customField.isEnabled = false
        } else {
            modelPopup.selectItem(withTitle: Self.customTitle)
            customField.stringValue = snapshot.llmModel
            customField.isEnabled = true
        }
        tokensStepper.integerValue = snapshot.llmMaxTokens
        tokensField.stringValue = "\(snapshot.llmMaxTokens)"
        if snapshot.llmEnabled {
            readyLabel.stringValue = snapshot.llmReady
                ? "狀態：就緒"
                : "狀態：尚未就緒（缺少 Cerebras API key）。仍可儲存，實際管線會降級回原始 STT。"
        } else {
            readyLabel.stringValue = "狀態：已停用"
        }
        isRefreshing = false
    }

    @objc private func modelPopupChanged() {
        guard !isRefreshing else { return }
        customField.isEnabled = modelPopup.titleOfSelectedItem == Self.customTitle
    }

    @objc private func tokensStepped() {
        tokensField.stringValue = "\(tokensStepper.integerValue)"
    }

    @objc private func applyTapped() {
        let model: String
        if modelPopup.titleOfSelectedItem == Self.customTitle {
            model = customField.stringValue
        } else {
            model = Self.presetModel
        }
        apply(.llm(enabled: enableBox.state == .on,
                   model: model,
                   maxTokens: tokensStepper.integerValue))
    }
}
