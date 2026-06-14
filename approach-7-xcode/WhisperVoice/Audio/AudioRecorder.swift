import AVFoundation

/// Records from the selected input device via AVAudioEngine, converts to
/// 16 kHz mono PCM16, and writes a temp WAV. Mirrors approach-6 `_voice_audio.py`.
final class AudioRecorder {
    private let sampleRate: Double
    private let deviceSpec: InputDeviceSpec
    private let beepThresholdSamples: Int

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private var file: AVAudioFile?
    private var fileURL: URL?

    private(set) var bufferSamples: Int = 0
    private(set) var isRecording = false
    private var beepFired = false

    /// Called once (on an audio thread) when accumulated samples first exceed the beep threshold.
    var onBeepThreshold: (() -> Void)?

    init(config: RecordingConfig) {
        self.sampleRate = Double(config.sampleRate)
        self.deviceSpec = config.inputDevice
        self.beepThresholdSamples = 4000   // ~0.25s at 16k, matches approach-6
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

    func start() {
        bufferSamples = 0
        beepFired = false

        // Device selection (best-effort; falls back to default).
        if let devID = CoreAudioDevices.find(deviceSpec), let au = engine.inputNode.audioUnit {
            var mutableID = devID
            let st = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &mutableID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
            if st != noErr { AppLog.warn("⚠️ 設定錄音裝置失敗 status=\(st)，改用系統預設") }
        }
        AppLog.info("🎙️ 錄音裝置：\(currentDeviceLabel())")

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

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
        do {
            file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
            fileURL = url
        } catch {
            AppLog.error("❌ 無法建立 WAV 檔：\(error)")
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            isRecording = true
        } catch {
            AppLog.error("❌ 錄音啟動失敗（可能未授權麥克風）：\(error)")
            input.removeTap(onBus: 0)
            file = nil
            fileURL = nil
        }
    }

    private func process(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter, let file else { return }
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return inputBuffer
        }
        if err != nil || out.frameLength == 0 { return }
        do { try file.write(from: out) } catch { return }

        bufferSamples += Int(out.frameLength)
        if !beepFired && bufferSamples > beepThresholdSamples {
            beepFired = true
            onBeepThreshold?()
        }
    }

    /// Stop recording. Returns (wavURL, seconds). nil URL if < 0.5s (ignored).
    /// Caller owns the returned file and must delete it after use.
    func stop() -> (URL?, Double) {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRecording = false
        }
        let frames = bufferSamples
        let duration = Double(frames) / sampleRate
        let url = fileURL
        file = nil          // flush & close
        fileURL = nil
        converter = nil

        guard let url else { return (nil, 0.0) }
        if duration < 0.5 {
            try? FileManager.default.removeItem(at: url)
            return (nil, duration)
        }
        return (url, duration)
    }
}
