import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Paste pipeline. Mirrors approach-6 `_voice_paste.py` but native:
/// NSWorkspace frontmost app + NSPasteboard + CGEvent Cmd+V synthesis.
enum Paste {
    /// Non-blocking system beep (matches approach-6 `afplay Tink.aiff &`).
    static func beep() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        task.arguments = ["/System/Library/Sounds/Tink.aiff"]
        try? task.run()
    }

    /// Current frontmost application (replaces approach-6 osascript).
    static func frontmostApp() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// Whether this process is trusted for Accessibility (required for CGEvent paste).
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility (shows system dialog if not trusted).
    @discardableResult
    static func promptAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Copy text and synthesize Cmd+V into the target app.
    /// Returns (method, ok). Falls back to clipboard-only without Accessibility.
    static func pasteText(_ text: String, targetApp: NSRunningApplication?) async -> (method: String, ok: Bool) {
        let activationSettleNs = await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            if let app = targetApp {
                let wasActive = app.isActive
                if !wasActive {
                    if #available(macOS 14.0, *) {
                        app.activate()
                    } else {
                        app.activate(options: [])
                    }
                }
                return activationSettleNanoseconds(targetWasActive: wasActive)
            }
            return UInt64(0)
        }

        // The target normally stays frontmost while a menu-bar hotkey is in use.
        // Only pay the activation settle cost when focus actually had to change.
        if activationSettleNs > 0 {
            try? await Task.sleep(nanoseconds: activationSettleNs)
        }

        guard isAccessibilityTrusted() else {
            AppLog.warn("⚠️ 未取得「輔助使用」授權，文字已存剪貼簿，請手動 Cmd+V")
            AppLog.warn("   系統設定 → 隱私權與安全性 → 輔助使用 → 允許 VoiceKey")
            return ("clipboard_only", false)
        }

        let ok = await MainActor.run { synthesizeCmdV() }
        return ok ? ("cgevent", true) : ("clipboard_only", false)
    }

    static func activationSettleNanoseconds(targetWasActive: Bool) -> UInt64 {
        targetWasActive ? 0 : 120_000_000
    }

    private static func synthesizeCmdV() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
