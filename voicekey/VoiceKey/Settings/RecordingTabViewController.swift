import AppKit

final class RecordingTabViewController: SettingsTabViewController {
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let ratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rescanButton = NSButton(title: "重新掃描", target: nil, action: nil)
    private let applyButton = NSButton(title: "套用錄音設定", target: nil, action: nil)
    private var isRefreshing = false

    private static let systemDefaultTitle = "系統預設"

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 260))
        self.view = view
        let stack = Self.stack(in: view)

        rescanButton.target = self
        rescanButton.action = #selector(rescan)
        applyButton.target = self
        applyButton.action = #selector(applyTapped)
        applyButton.keyEquivalent = "\r"

        stack.addArrangedSubview(Self.heading("輸入裝置"))
        let deviceRow = NSStackView(views: [devicePopup, rescanButton])
        deviceRow.orientation = .horizontal
        deviceRow.alignment = .centerY
        deviceRow.spacing = 8
        devicePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(deviceRow)
        stack.addArrangedSubview(Self.help("USB 熱插拔後按「重新掃描」。套用後於下次錄音生效。"))

        stack.addArrangedSubview(Self.heading("取樣率"))
        ratePopup.removeAllItems()
        for rate in SettingsLimits.sampleRates {
            ratePopup.addItem(withTitle: "\(rate) Hz")
            ratePopup.lastItem?.representedObject = rate
        }
        stack.addArrangedSubview(ratePopup)
        stack.addArrangedSubview(applyButton)
        stack.addArrangedSubview(Self.help("變更裝置或取樣率會重建錄音元件；錄音或辨識進行中無法套用。"))
    }

    override func refresh() {
        isRefreshing = true
        rebuildDeviceList()
        if let idx = SettingsLimits.sampleRates.firstIndex(of: snapshot.sampleRate) {
            ratePopup.selectItem(at: idx)
        }
        isRefreshing = false
    }

    private func rebuildDeviceList() {
        devicePopup.removeAllItems()
        devicePopup.addItem(withTitle: Self.systemDefaultTitle)
        for device in snapshot.inputDevices {
            devicePopup.addItem(withTitle: device.name)
        }
        selectCurrentDevice()
    }

    private func selectCurrentDevice() {
        switch snapshot.inputDevice {
        case .systemDefault:
            devicePopup.selectItem(at: 0)
        case .name(let name):
            if devicePopup.itemTitles.contains(name) {
                devicePopup.selectItem(withTitle: name)
            } else {
                devicePopup.selectItem(at: 0)
            }
        case .candidates(let names):
            if let match = names.first(where: { devicePopup.itemTitles.contains($0) }) {
                devicePopup.selectItem(withTitle: match)
            } else {
                devicePopup.selectItem(at: 0)
            }
        case .index(let i):
            let titles = devicePopup.itemTitles.dropFirst()
            if i >= 0, i < titles.count {
                devicePopup.selectItem(at: i + 1)
            } else {
                devicePopup.selectItem(at: 0)
            }
        }
    }

    private func selectedDevice() -> InputDeviceSpec {
        if devicePopup.indexOfSelectedItem <= 0 {
            return .systemDefault
        }
        return .name(devicePopup.titleOfSelectedItem ?? "")
    }

    private func selectedRate() -> Int {
        (ratePopup.selectedItem?.representedObject as? Int) ?? snapshot.sampleRate
    }

    @objc private func rescan() {
        if let snap = applier?.settingsSnapshot() {
            reload(snap)
        }
    }

    @objc private func applyTapped() {
        apply(.recording(sampleRate: selectedRate(), inputDevice: selectedDevice()))
    }
}
