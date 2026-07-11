import AVFoundation

/// Records from the selected input device via AVAudioEngine, mirrors approach-6 `_voice_audio.py`.
///
/// Design: audio thread only accumulates PCMBuffers in memory (like Python's frames list).
/// Conversion to 16k mono PCM16 WAV happens in stop() on the calling thread,
/// away from the real-time audio thread.
///
/// macOS 26 notes:
/// - engine is recreated each start() — reusing a stopped AVAudioEngine causes NSException
///   on second installTap (engine internal state not fully reset after stop()).
/// - installTap must be called BEFORE engine.start(); taps added after prepare() with
///   format:nil do not receive audio callbacks on macOS 26.
/// - format:nil still used (not a specific AVAudioFormat) because passing a non-native
///   AVAudioFormat to InstallTapOnNode throws NSException via AVAudioEngineImpl.
final class AudioRecorder {
    private let sampleRate: Double
    private let deviceSpec: InputDeviceSpec
    private let beepThresholdSamples: Int
    private let targetFormat: AVAudioFormat

    // var, not let — recreated each recording so macOS 26 doesn't
    // throw NSException on a second installTap on a reused stopped engine.
    private var engine = AVAudioEngine()

    // Audio thread writes; main thread reads only after engine.stop().
    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var capturedFormat: AVAudioFormat?

    private(set) var bufferSamples: Int = 0
    private(set) var isRecording = false
    private var beepFired = false

    /// Called once on the audio thread when enough samples are buffered for a beep cue.
    var onBeepThreshold: (() -> Void)?

    init(config: RecordingConfig) {
        self.sampleRate = Double(config.sampleRate)
        self.deviceSpec = config.inputDevice
        self.beepThresholdSamples = 4000   // ~0.25 s at 16 k, matches approach-6
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: Double(config.sampleRate),
                                          channels: 1,
                                          interleaved: false)!
    }

    func currentDeviceLabel() -> String {
        if let id = CoreAudioDevices.find(deviceSpec), let name = CoreAudioDevices.deviceName(id) {
            return "\(id):\(name)"
        }
        return "system default input"
    }

    @discardableResult
    func start() -> Bool {
        bufferSamples = 0
        beepFired = false
        capturedBuffers = []
        capturedFormat = nil
        isRecording = false

        // Fresh engine — avoids macOS 26 NSException on second installTap
        // when reusing a stopped AVAudioEngine (engine state not fully reset after stop()).
        engine = AVAudioEngine()
        let input = engine.inputNode

        // Accessing inputNode.audioUnit before prepare() lazily allocates AUHAL,
        // allowing device selection without calling prepare() explicitly.
        if let devID = CoreAudioDevices.find(deviceSpec), let au = input.audioUnit {
            var mutableID = devID
            let st = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &mutableID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
            if st != noErr { AppLog.warn("⚠️ 設定錄音裝置失敗 status=\(st)，改用系統預設") }
        }
        AppLog.info("🎙️ 錄音裝置：\(currentDeviceLabel())")

        // CRITICAL: after changing the device via AudioUnitSetProperty, inputNode.outputFormat
        // stays stale (it reflects the device present at engine-creation time). format:nil would
        // use that stale format → mismatch with the new device's hardware → -10868
        // (kAudioUnitErr_FormatNotSupported) at start(). inputFormat(forBus:0) queries the live
        // AUHAL and returns the SELECTED device's true hardware format, so the chain matches.
        let hwFormat = input.inputFormat(forBus: 0)
        AppLog.info("🎙️ 硬體格式：\(hwFormat.sampleRate) Hz \(hwFormat.channelCount)ch")
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            AppLog.error("❌ 取得硬體格式失敗（sampleRate=\(hwFormat.sampleRate)）")
            return false
        }

        // Install tap BEFORE engine.start() — on macOS 26, taps installed after prepare()
        // may not fire. Use the live hardware format (not nil) so the device change is honoured.
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buf, _ in
            self?.collect(buf)
        }

        do {
            try engine.start()
            isRecording = true
            return true
        } catch {
            AppLog.error("❌ 錄音啟動失敗（可能未授權麥克風）：\(error)")
            input.removeTap(onBus: 0)
            isRecording = false
            return false
        }
    }

    // Called on real-time audio thread — no allocation beyond buffer copy, no disk I/O.
    private func collect(_ buffer: AVAudioPCMBuffer) {
        if capturedFormat == nil { capturedFormat = buffer.format }
        if let copy = shallowCopy(buffer) {
            capturedBuffers.append(copy)
        }
        bufferSamples += Int(buffer.frameLength)
        if !beepFired && bufferSamples > beepThresholdSamples {
            beepFired = true
            onBeepThreshold?()
        }
    }

    private func shallowCopy(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: src.format,
                                         frameCapacity: src.frameLength) else { return nil }
        dst.frameLength = src.frameLength
        let chCount = Int(src.format.channelCount)
        if src.format.commonFormat == .pcmFormatFloat32,
           let s = src.floatChannelData, let d = dst.floatChannelData {
            for ch in 0..<chCount {
                memcpy(d[ch], s[ch], Int(src.frameLength) * MemoryLayout<Float32>.size)
            }
            return dst
        }
        if src.format.commonFormat == .pcmFormatInt16,
           let s = src.int16ChannelData, let d = dst.int16ChannelData {
            for ch in 0..<chCount {
                memcpy(d[ch], s[ch], Int(src.frameLength) * MemoryLayout<Int16>.size)
            }
            return dst
        }
        return nil
    }

    /// Stop recording. Returns (wavURL, duration). nil URL if < 0.5 s (ignored).
    /// Conversion and WAV write happen here, on the calling (main) thread.
    /// Caller owns the returned file and must delete it after use.
    func stop() -> (URL?, Double) {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()      // blocks until audio thread is fully stopped
            isRecording = false
        }

        guard let hwFmt = capturedFormat, !capturedBuffers.isEmpty else { return (nil, 0.0) }

        let duration = Double(bufferSamples) / hwFmt.sampleRate
        if duration < 0.5 {
            capturedBuffers = []
            return (nil, duration)
        }

        return writeWAV(buffers: capturedBuffers, hwFormat: hwFmt, duration: duration)
    }

    private func writeWAV(buffers: [AVAudioPCMBuffer],
                          hwFormat: AVAudioFormat,
                          duration: Double) -> (URL?, Double) {
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            AppLog.error("❌ AVAudioConverter 初始化失敗（\(hwFormat.sampleRate)→\(sampleRate)）")
            return (nil, 0.0)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whispervoice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false) else {
            AppLog.error("❌ 無法建立 WAV 檔")
            return (nil, 0.0)
        }

        let ratio = targetFormat.sampleRate / hwFormat.sampleRate
        for inputBuffer in buffers {
            let cap = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { continue }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return inputBuffer
            }
            if out.frameLength > 0 { try? file.write(from: out) }
        }

        capturedBuffers = []
        AppLog.info("💾 WAV 已存：\(url.lastPathComponent)（\(String(format: "%.1f", duration))s）")
        return (url, duration)
    }
}
