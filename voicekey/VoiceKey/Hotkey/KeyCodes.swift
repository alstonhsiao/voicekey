import Carbon.HIToolbox

/// Maps config key/modifier names to Carbon virtual key codes & modifier masks.
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

    /// Carbon modifier mask for a single modifier name. Empty/unknown -> 0.
    static func modifierFlags(_ name: String) -> UInt32 {
        switch name.lowercased() {
        case "ctrl", "control": return UInt32(controlKey)
        case "shift":           return UInt32(shiftKey)
        case "alt", "option":   return UInt32(optionKey)
        case "cmd", "command":  return UInt32(cmdKey)
        default:                return 0
        }
    }
}
