import Carbon.HIToolbox
import Foundation

struct HotkeySpec {
    let keyCode: UInt32
    let modifiers: UInt32
    let action: () -> Void
}

/// Testable registration backend. Production uses Carbon; tests inject a mock.
protocol HotkeyBackend: AnyObject {
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool
    func unregister(id: UInt32)
    func unregisterAll()
}

final class CarbonHotkeyBackend: HotkeyBackend {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private let signature: FourCharCode

    init(signature: FourCharCode) {
        self.signature = signature
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            AppLog.warn("⚠️ 熱鍵註冊失敗 keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
            return false
        }
        refs[id] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }
}

/// Global hotkeys via Carbon `RegisterEventHotKey`.
/// Key advantage over pynput: does NOT require the "Input Monitoring" permission.
final class HotkeyManager {
    private var actions: [UInt32: () -> Void] = [:]
    private var specs: [(id: UInt32, spec: HotkeySpec)] = []
    private var handlerRef: EventHandlerRef?
    private let signature: FourCharCode = fourCharCode("WHSP")
    private var nextId: UInt32 = 1
    private let backend: HotkeyBackend
    private let ownsHandler: Bool

    init(backend: HotkeyBackend? = nil) {
        if let backend {
            self.backend = backend
            self.ownsHandler = false
        } else {
            self.backend = CarbonHotkeyBackend(signature: signature)
            self.ownsHandler = true
            installHandler()
        }
    }

    deinit {
        unregisterAll()
        if ownsHandler, let handlerRef { RemoveEventHandler(handlerRef) }
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
        register(HotkeySpec(keyCode: keyCode, modifiers: modifiers, action: action))
    }

    @discardableResult
    func register(_ spec: HotkeySpec) -> Bool {
        let id = nextId
        nextId += 1
        guard backend.register(id: id, keyCode: spec.keyCode, modifiers: spec.modifiers) else {
            return false
        }
        actions[id] = spec.action
        specs.append((id: id, spec: spec))
        return true
    }

    func unregisterAll() {
        backend.unregisterAll()
        actions.removeAll()
        specs.removeAll()
    }

    /// Replace all hotkeys. On any failure, restore the previous set.
    /// Returns false (and restores) if a new registration fails or if restore fails.
    @discardableResult
    func reconfigure(_ newSpecs: [HotkeySpec]) -> Bool {
        let oldSpecs = specs.map(\.spec)
        unregisterAll()

        var registered: [HotkeySpec] = []
        for spec in newSpecs {
            if register(spec) {
                registered.append(spec)
            } else {
                unregisterAll()
                var restored = true
                for old in oldSpecs {
                    if !register(old) { restored = false }
                }
                if !restored {
                    AppLog.error("❌ 熱鍵回復失敗，部分熱鍵可能無法使用")
                }
                return false
            }
        }
        return true
    }

    var registeredCount: Int { specs.count }

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
