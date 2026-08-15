import AppKit
import Carbon.HIToolbox

/// Maps config key/modifier names to Carbon virtual key codes & modifier masks.
/// F1–F20 use an explicit table (Carbon codes are not a contiguous range).
enum KeyCodes {
    static let functionKeys: [String: UInt32] = [
        "f1": UInt32(kVK_F1),   "f2": UInt32(kVK_F2),   "f3": UInt32(kVK_F3),
        "f4": UInt32(kVK_F4),   "f5": UInt32(kVK_F5),   "f6": UInt32(kVK_F6),
        "f7": UInt32(kVK_F7),   "f8": UInt32(kVK_F8),   "f9": UInt32(kVK_F9),
        "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
        "f13": UInt32(kVK_F13), "f14": UInt32(kVK_F14), "f15": UInt32(kVK_F15),
        "f16": UInt32(kVK_F16), "f17": UInt32(kVK_F17), "f18": UInt32(kVK_F18),
        "f19": UInt32(kVK_F19), "f20": UInt32(kVK_F20),
    ]

    static func keyCode(for name: String) -> UInt32? {
        functionKeys[name.lowercased()]
    }

    /// Reverse lookup. Returns canonical "F1"…"F20", never a numeric range guess.
    static func functionKeyName(for keyCode: UInt32) -> String? {
        guard let raw = functionKeys.first(where: { $0.value == keyCode })?.key else {
            return nil
        }
        return raw.uppercased()
    }

    static func isSupportedFunctionKey(_ name: String) -> Bool {
        keyCode(for: name) != nil
    }

    /// Carbon modifier mask. Supports a single name or combinations ("ctrl+shift").
    static func modifierFlags(_ name: String) -> UInt32 {
        var flags: UInt32 = 0
        let parts = name.lowercased().split { $0 == "+" || $0 == "," || $0 == "|" || $0 == " " }
        for part in parts {
            switch part {
            case "ctrl", "control": flags |= UInt32(controlKey)
            case "shift":           flags |= UInt32(shiftKey)
            case "alt", "option":   flags |= UInt32(optionKey)
            case "cmd", "command":  flags |= UInt32(cmdKey)
            default:                break
            }
        }
        return flags
    }

    static func hasSupportedModifier(_ name: String) -> Bool {
        modifierFlags(name) != 0
    }

    /// Canonical stored form: "ctrl", "ctrl+shift", "cmd+option".
    static func modifierName(from flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        return parts.joined(separator: "+")
    }

    static func displayString(key: String, modifier: String) -> String {
        let symbols = modifier.lowercased()
            .split { $0 == "+" || $0 == "," || $0 == "|" || $0 == " " }
            .map { part -> String in
                switch part {
                case "ctrl", "control": return "⌃"
                case "shift": return "⇧"
                case "option", "alt": return "⌥"
                case "cmd", "command": return "⌘"
                default: return String(part)
                }
            }
            .joined()
        return symbols + key.uppercased()
    }
}
