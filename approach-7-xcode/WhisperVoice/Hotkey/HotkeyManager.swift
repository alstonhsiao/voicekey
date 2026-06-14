import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey`.
/// Key advantage over pynput: does NOT require the "Input Monitoring" permission.
/// Mirrors approach-6's Ctrl+F1 (record toggle) / Ctrl+F10 (mode cycle).
final class HotkeyManager {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private let signature: FourCharCode = fourCharCode("WHSP")
    private var nextId: UInt32 = 1

    init() {
        installHandler()
    }

    deinit {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData, let event else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if st == noErr { manager.handle(id: hkID.id) }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    /// Register a hotkey. Returns false if registration fails (e.g. key in use).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        let id = nextId
        nextId += 1
        actions[id] = action
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            AppLog.warn("⚠️ 熱鍵註冊失敗 keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
            actions[id] = nil
            return false
        }
        refs.append(ref)
        return true
    }

    private func handle(id: UInt32) {
        guard let action = actions[id] else { return }
        DispatchQueue.main.async { action() }
    }
}

/// Build a FourCharCode from up to 4 ASCII chars.
func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(byte)
    }
    return result
}
