import AppKit
import Carbon.HIToolbox

/// Click to capture a modifier + F1–F20 combo. Escape cancels.
final class HotkeyRecorderField: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var keyName: String
    private(set) var modifierName: String
    private var isCapturing = false
    var onChange: ((String, String) -> Void)?

    init(key: String, modifier: String) {
        self.keyName = key
        self.modifierName = modifier
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 24) }

    func setCombo(key: String, modifier: String) {
        keyName = key
        modifierName = modifier
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isCapturing = true
        refresh()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isCapturing = false
        refresh()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isCapturing = false
            window?.makeFirstResponder(nil)
            refresh()
            return
        }
        guard let name = KeyCodes.functionKeyName(for: UInt32(event.keyCode)) else {
            NSSound.beep()
            return
        }
        let mods = KeyCodes.modifierName(from: event.modifierFlags)
        guard !mods.isEmpty else {
            NSSound.beep()
            return
        }
        keyName = name
        modifierName = mods
        isCapturing = false
        onChange?(name, mods)
        window?.makeFirstResponder(nil)
        refresh()
    }

    private func refresh() {
        if isCapturing {
            label.stringValue = "按下熱鍵…"
            label.textColor = .secondaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            label.stringValue = KeyCodes.displayString(key: keyName, modifier: modifierName)
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
