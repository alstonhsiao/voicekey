import CoreAudio
import Foundation

/// CoreAudio input-device enumeration & name-based selection.
/// Mirrors approach-6's `_find_device_by_name` (exact → partial) + candidate list.
enum CoreAudioDevices {
    struct Device {
        let id: AudioDeviceID
        let name: String
        let inputChannels: Int
    }

    static func allInputDevices() -> [Device] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        var result: [Device] = []
        for id in ids {
            let ch = inputChannelCount(id)
            if ch > 0, let name = deviceName(id) {
                result.append(Device(id: id, name: name, inputChannels: ch))
            }
        }
        return result
    }

    static func deviceName(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }

    static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buffer in abl { channels += Int(buffer.mNumberChannels) }
        return channels
    }

    /// Resolve a config InputDeviceSpec to an AudioDeviceID. nil = system default.
    static func find(_ spec: InputDeviceSpec) -> AudioDeviceID? {
        resolve(spec)?.id
    }

    /// Resolve once and retain both ID and display name. Callers that already
    /// enumerated devices can pass that snapshot to avoid another HAL query.
    static func resolve(_ spec: InputDeviceSpec, in devices: [Device]? = nil) -> Device? {
        switch spec {
        case .systemDefault:
            return nil
        case .index(let i):
            let available = devices ?? allInputDevices()
            return (i >= 0 && i < available.count) ? available[i] : nil
        case .name(let n):
            return matchByName(n, in: devices ?? allInputDevices())
        case .candidates(let names):
            let available = devices ?? allInputDevices()
            for n in names {
                if let device = matchByName(n, in: available) {
                    AppLog.info("🎙️ 自動選擇裝置：\(n)")
                    return device
                }
            }
            AppLog.warn("⚠️ 候選裝置均不可用，改用系統預設輸入")
            return nil
        }
    }

    private static func matchByName(_ name: String, in devices: [Device]) -> Device? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = devices.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == needle
        }) {
            return exact
        }
        if let partial = devices.first(where: { $0.name.lowercased().contains(needle) }) {
            return partial
        }
        return nil
    }
}
