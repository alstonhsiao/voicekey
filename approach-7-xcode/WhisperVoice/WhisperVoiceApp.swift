import AppKit

// @main entry point. No file named main.swift, so @main is valid.
// AppKit menu bar agent (LSUIElement). Activation policy set to .accessory
// (no Dock icon) — redundant with Info.plist LSUIElement=YES but harmless.
@main
enum WhisperVoiceApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
