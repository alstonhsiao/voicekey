import AppKit

final class APIKeysTabViewController: SettingsTabViewController {
    private let xaiField = NSSecureTextField(string: "")
    private let cereField = NSSecureTextField(string: "")
    private let xaiSource = SettingsTabViewController.help("")
    private let cereSource = SettingsTabViewController.help("")
    private let overrideWarning = SettingsTabViewController.help("")
    private let saveButton = NSButton(title: "儲存金鑰", target: nil, action: nil)
    private let clearXAI = NSButton(title: "清除 XAI", target: nil, action: nil)
    private let clearCere = NSButton(title: "清除 Cerebras", target: nil, action: nil)

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        self.view = view
        let stack = Self.stack(in: view)

        xaiField.placeholderString = "XAI_API_KEY"
        cereField.placeholderString = "CEREBRAS_API_KEY"
        for field in [xaiField, cereField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        }
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        clearXAI.target = self
        clearXAI.action = #selector(clearXAITapped)
        clearCere.target = self
        clearCere.action = #selector(clearCereTapped)

        stack.addArrangedSubview(Self.heading("API 金鑰"))
        stack.addArrangedSubview(Self.help("金鑰只寫入鑰匙圈，不會寫入 config.local.json 或 log。空白欄位在按「儲存金鑰」時視為不變更。"))
        stack.addArrangedSubview(Self.labeledRow("XAI / Grok", xaiField))
        stack.addArrangedSubview(xaiSource)
        stack.addArrangedSubview(Self.labeledRow("Cerebras", cereField))
        stack.addArrangedSubview(cereSource)
        stack.addArrangedSubview(overrideWarning)
        let buttons = NSStackView(views: [saveButton, clearXAI, clearCere])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)
    }

    override func refresh() {
        xaiField.stringValue = ""
        cereField.stringValue = ""
        xaiField.placeholderString = snapshot.xaiHasKeychainValue ? "鑰匙圈已有儲存的金鑰" : "尚未儲存"
        cereField.placeholderString = snapshot.cerebrasHasKeychainValue ? "鑰匙圈已有儲存的金鑰" : "尚未儲存"
        xaiSource.stringValue = sourceLine("XAI", snapshot.xaiSource)
        cereSource.stringValue = sourceLine("Cerebras", snapshot.cerebrasSource)
        let blocked = snapshot.xaiSource.usesHigherPriorityThanKeychain
            || snapshot.cerebrasSource.usesHigherPriorityThanKeychain
        overrideWarning.isHidden = !blocked
        if blocked {
            var parts: [String] = ["目前由較高優先來源控制，Keychain 變更不會立即生效。"]
            if snapshot.xaiSource.kind == .envFile || snapshot.cerebrasSource.kind == .envFile,
               let path = snapshot.xaiSource.envFilePath ?? snapshot.cerebrasSource.envFilePath {
                parts.append("來源檔：\(path)")
            }
            overrideWarning.stringValue = parts.joined(separator: " ")
        }
    }

    private func sourceLine(_ name: String, _ info: SecretSourceInfo) -> String {
        var line = "\(name) 目前來源：\(info.displayName)"
        if info.kind == .envFile, let path = info.envFilePath {
            line += "（\(path)）"
        }
        return line
    }

    @objc private func saveTapped() {
        let xaiText = xaiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cereText = cereField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(.apiKeys(xai: xaiText.isEmpty ? .unchanged : .set(xaiText),
                       cerebras: cereText.isEmpty ? .unchanged : .set(cereText)))
    }

    @objc private func clearXAITapped() {
        apply(.apiKeys(xai: .clear, cerebras: .unchanged))
    }

    @objc private func clearCereTapped() {
        apply(.apiKeys(xai: .unchanged, cerebras: .clear))
    }
}
