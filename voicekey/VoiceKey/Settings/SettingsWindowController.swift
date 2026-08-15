import AppKit

final class SettingsWindowController: NSWindowController {
    private let applier: SettingsApplying
    private let tabs: SettingsRootTabController
    private let general: GeneralTabViewController
    private let hotkeys: HotkeyTabViewController
    private let recording: RecordingTabViewController
    private let apiKeys: APIKeysTabViewController
    private let llm: LLMTabViewController

    init(applier: SettingsApplying) {
        self.applier = applier
        let snap = applier.settingsSnapshot()

        general = GeneralTabViewController(applier: applier, snapshot: snap)
        general.title = "一般"
        hotkeys = HotkeyTabViewController(applier: applier, snapshot: snap)
        hotkeys.title = "熱鍵"
        recording = RecordingTabViewController(applier: applier, snapshot: snap)
        recording.title = "錄音"
        apiKeys = APIKeysTabViewController(applier: applier, snapshot: snap)
        apiKeys.title = "API 金鑰"
        llm = LLMTabViewController(applier: applier, snapshot: snap)
        llm.title = "LLM"

        tabs = SettingsRootTabController()
        tabs.tabStyle = .segmentedControlOnTop
        tabs.addChild(general)
        tabs.addChild(hotkeys)
        tabs.addChild(recording)
        tabs.addChild(apiKeys)
        tabs.addChild(llm)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceKey 設定"
        window.minSize = NSSize(width: 500, height: 380)
        window.contentViewController = tabs
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
        tabs.onSelect = { [weak self] in self?.reloadFromApplier() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        reloadFromApplier()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }

    func reloadFromApplier() {
        let snap = applier.settingsSnapshot()
        general.reload(snap)
        hotkeys.reload(snap)
        recording.reload(snap)
        apiKeys.reload(snap)
        llm.reload(snap)
    }
}
