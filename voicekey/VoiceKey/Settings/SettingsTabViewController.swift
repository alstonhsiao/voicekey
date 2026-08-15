import AppKit

/// Shared base for Settings tabs: snapshot refresh + NSAlert on apply failure.
class SettingsTabViewController: NSViewController {
    weak var applier: SettingsApplying?
    var snapshot: SettingsSnapshot

    init(applier: SettingsApplying, snapshot: SettingsSnapshot) {
        self.applier = applier
        self.snapshot = snapshot
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload(_ snapshot: SettingsSnapshot) {
        self.snapshot = snapshot
        guard isViewLoaded else { return }
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refresh() {}

    func apply(_ change: SettingsChange) {
        do {
            try applier?.apply(change)
            if let snap = applier?.settingsSnapshot() {
                reload(snap)
            }
        } catch {
            presentApplyError(error)
            if let snap = applier?.settingsSnapshot() {
                reload(snap)
            }
        }
    }

    func presentApplyError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "無法套用設定"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "確定")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Form helpers

    static func stack(in view: NSView) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
        return stack
    }

    static func heading(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        return f
    }

    static func help(_ text: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.textColor = .secondaryLabelColor
        f.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        f.preferredMaxLayoutWidth = 460
        return f
    }

    static func checkbox(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: target, action: action)
        return b
    }

    static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        NSButton(title: title, target: target, action: action)
    }

    static func popup(target: AnyObject, action: Selector) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.target = target
        p.action = action
        p.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return p
    }

    static func labeledRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        return row
    }
}

/// Root tab controller that refreshes the active tab when the selection changes.
final class SettingsRootTabController: NSTabViewController {
    var onSelect: (() -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelect?()
    }
}
