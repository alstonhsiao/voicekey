import AppKit

enum VoiceState: String {
    case idle, recording, processing, error
}

/// Orchestrates the record → transcribe → correct → (paste) → (log) pipeline.
/// Mirrors approach-6 `main.py`. Phase 3: STT + LLM, logs final text (no paste yet).
final class VoiceController {
    private let config: AppConfig
    private let modeManager: ModeManager
    private let recorder: AudioRecorder
    private let transcribe: TranscribeProvider
    private let llm: LLMCorrectionProvider?
    private let vocab: VocabStores
    private let sessionLogger: SessionLogger
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    // Separate serial queues so a stuck start() cannot block stop() (and vice
    // versa). timerQueue drives timeout fallbacks that force-recover state if
    // a CoreAudio HAL call hangs (TROUBLESHOOTING 1d/1e).
    private let startQueue = DispatchQueue(label: "com.alston.VoiceKey.start")
    private let stopQueue = DispatchQueue(label: "com.alston.VoiceKey.stop")
    private let timerQueue = DispatchQueue(label: "com.alston.VoiceKey.timer")

    private var isRecording = false
    private var isProcessing = false   // blocks new recording while transcribing
    private let lock = NSLock()

    /// Phase 4: menu bar observes state changes.
    var onStateChange: ((VoiceState) -> Void)?

    /// Thread-safe: recording or in-flight transcription. Settings must not rebuild while busy.
    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return isRecording || isProcessing
    }

    var currentState: VoiceState {
        lock.lock(); defer { lock.unlock() }
        if isRecording { return .recording }
        if isProcessing { return .processing }
        return .idle
    }

    init(config: AppConfig,
         modeManager: ModeManager,
         transcribe: TranscribeProvider,
         llm: LLMCorrectionProvider?,
         vocab: VocabStores,
         sessionLogger: SessionLogger) {
        self.config = config
        self.modeManager = modeManager
        self.transcribe = transcribe
        self.llm = llm
        self.vocab = vocab
        self.sessionLogger = sessionLogger
        self.recorder = AudioRecorder(config: config.recording)
        self.recorder.onBeepThreshold = { Paste.beep() }
    }

    func toggleRecord() {
        lock.lock()
        if !isRecording {
            if isProcessing {
                lock.unlock()
                AppLog.warn("⚠️ 辨識進行中，請稍後再錄音")
                return
            }
            isRecording = true
            lock.unlock()
            startRecording()
        } else {
            isRecording = false
            isProcessing = true
            lock.unlock()
            let target = Paste.frontmostApp()   // capture before focus can change
            processRecording(targetApp: target)
        }
    }

    func cycleMode() {
        modeManager.cycle()
        AppLog.info("🔀 模式 → \(modeManager.current.display)")
    }

    private func setState(_ s: VoiceState) {
        onStateChange?(s)
    }

    private func startRecording() {
        vocab.maybeReloadAll()   // hot-reload all three layers (matches approach-6)
        setState(.recording)
        AppLog.info("🔴 錄音中... [\(modeManager.current.display)]（再按一次停止）")
        startQueue.async { [weak self] in
            guard let self else { return }
            let ok = self.recorder.start()
            guard !ok else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let shouldReset = self.isRecording
                if shouldReset { self.isRecording = false }
                self.lock.unlock()
                if shouldReset {
                    self.setState(.error)
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.setState(.idle)
                    }
                }
            }
        }
    }

    private func processRecording(targetApp: NSRunningApplication?) {
        // Merge STT keyterms per recording (vocab layers were hot-reloaded at
        // record start): user vocab + layer1 first, then the mode's base list.
        var mode = modeManager.current
        mode.grokKeyterms = vocab.effectiveKeyterms(for: mode,
                                                    limit: config.vocab.sttKeytermLimit)
        setState(.processing)
        Task {
            defer {
                lock.lock()
                isProcessing = false
                lock.unlock()
            }
            let pipelineStarted = DispatchTime.now()
            let stopStarted = DispatchTime.now()
            let (maybeURL, audioSec) = await stopRecorder()
            let stopMs = Self.elapsedMs(since: stopStarted)
            guard let url = maybeURL else {
                setState(.idle)
                if audioSec > 0 {
                    AppLog.warn("⚠️ 錄音時間太短，已忽略")
                } else {
                    AppLog.warn("⚠️ 停止錄音逾時，已取消此次辨識")
                }
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }
            let audioBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)

            AppLog.info("🔄 辨識中... [\(mode.display)]")

            // 1. STT
            let sttStarted = DispatchTime.now()
            let raw: String
            do {
                raw = try await transcribe.transcribe(wavURL: url, mode: mode)
            } catch let e as STTHTTPError {
                let sttMs = Self.elapsedMs(since: sttStarted)
                AppLog.error("❌ \(Self.httpMessage(e.status))")
                sessionLogger.log(SessionRecord(
                    timestamp: SessionLogger.now(), appVersion: appVersion, appBuild: appBuild,
                    modeId: mode.id, modeName: mode.name, provider: transcribe.name,
                    audioSec: (audioSec * 100).rounded() / 100, audioBytes: audioBytes,
                    stopMs: stopMs, sttMs: sttMs,
                    pipelineMs: Self.elapsedMs(since: pipelineStarted),
                    errorType: "http_error", errorDetail: "HTTP \(e.status)"))
                setState(.error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                setState(.idle)
                return
            } catch {
                let sttMs = Self.elapsedMs(since: sttStarted)
                let isTimeout = (error as? URLError)?.code == .timedOut
                AppLog.error(isTimeout ? "❌ 網路逾時" : "❌ 發生錯誤：\(error)")
                sessionLogger.log(SessionRecord(
                    timestamp: SessionLogger.now(), appVersion: appVersion, appBuild: appBuild,
                    modeId: mode.id, modeName: mode.name, provider: transcribe.name,
                    audioSec: (audioSec * 100).rounded() / 100, audioBytes: audioBytes,
                    stopMs: stopMs, sttMs: sttMs,
                    pipelineMs: Self.elapsedMs(since: pipelineStarted),
                    errorType: isTimeout ? "timeout" : "unknown", errorDetail: "\(error)"))
                setState(.error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                setState(.idle)
                return
            }
            let sttMs = Self.elapsedMs(since: sttStarted)
            AppLog.debug("🪵 raw STT: \(raw)")

            // 2. regex fallback corrections
            let regexStarted = DispatchTime.now()
            let corrected = RegexCorrections.apply(raw, rules: mode.regexRules)
            let regexMs = Self.elapsedMs(since: regexStarted)
            guard !corrected.isEmpty else {
                AppLog.warn("⚠️ 辨識結果為空")
                setState(.idle)
                return
            }
            AppLog.debug("🪵 regex corrected: \(corrected)")

            // 3. LLM correction (layer2 injection; degrade on failure)
            let llmStarted = DispatchTime.now()
            let usedLLM = (llm != nil && !mode.llmPrompt.isEmpty)
            var finalText = corrected
            if let llm, usedLLM {
                let injection = vocab.layer2.buildInjection()
                finalText = await llm.correct(text: corrected, mode: mode, extraSystemPrompt: injection)
                AppLog.debug("🪵 LLM corrected: \(finalText)")
            } else {
                AppLog.debug("🪵 LLM corrected: <skipped>")
            }
            let llmMs = Self.elapsedMs(since: llmStarted)
            let llmOut: String? = usedLLM ? finalText : nil

            // 3b. Layer-3 user vocab pinyin fuzzy (degrade to original on any issue)
            let vocabStarted = DispatchTime.now()
            var vocabOut: String?
            if let layer3 = vocab.layer3 {
                let applied = layer3.apply(finalText)
                if applied != finalText {
                    AppLog.debug("🪵 vocab corrected: \(applied)")
                }
                vocabOut = applied
                finalText = applied
            }
            let vocabMs = Self.elapsedMs(since: vocabStarted)

            // 4. paste into the target app
            let pasteStarted = DispatchTime.now()
            let (method, ok) = await Paste.pasteText(finalText, targetApp: targetApp)
            let pasteMs = Self.elapsedMs(since: pasteStarted)
            let pipelineMs = Self.elapsedMs(since: pipelineStarted)
            AppLog.info("⏱  stop: \(stopMs)ms | STT: \(sttMs)ms | regex: \(regexMs)ms | "
                        + "LLM: \(llmMs)ms | vocab: \(vocabMs)ms | paste: \(pasteMs)ms | "
                        + "pipeline: \(pipelineMs)ms | audio: \(String(format: "%.2f", audioSec))s")
            AppLog.info("✅ 已貼上（\(method)，ok=\(ok)）：\(finalText)")
            setState(.idle)

            sessionLogger.log(SessionRecord(
                timestamp: SessionLogger.now(),
                appVersion: appVersion, appBuild: appBuild,
                modeId: mode.id, modeName: mode.name, provider: transcribe.name,
                audioSec: (audioSec * 100).rounded() / 100,
                audioBytes: audioBytes, stopMs: stopMs,
                rawStt: raw, regexOut: corrected, regexMs: regexMs,
                llmOut: llmOut, vocabOut: vocabOut, vocabMs: vocabMs,
                finalText: finalText, sttMs: sttMs, llmMs: usedLLM ? llmMs : nil,
                pasteMethod: method, pasteOk: ok ? 1 : 0,
                pasteMs: pasteMs, pipelineMs: pipelineMs,
                llmFinishReason: llm?.lastFinishReason))
        }
    }

    private func stopRecorder() async -> (URL?, Double) {
        await withCheckedContinuation { continuation in
            // Use a dedicated queue separate from startQueue so a stuck
            // start() cannot block stop() on the same serial queue.
            let resumed = NSLock()
            var didResume = false
            func resumeOnce(_ value: (URL?, Double)) {
                resumed.lock()
                if didResume { resumed.unlock(); return }
                didResume = true
                resumed.unlock()
                continuation.resume(returning: value)
            }
            stopQueue.async { [weak self] in
                guard let self else {
                    resumeOnce((nil, 0.0))
                    return
                }
                resumeOnce(self.recorder.stop())
            }
            // Safety net: if recorder.stop() hangs (CoreAudio HAL), resume
            // after 5s so the pipeline can recover instead of staying stuck
            // in "辨識中" forever (TROUBLESHOOTING 1d/1e).
            timerQueue.asyncAfter(deadline: .now() + 5) {
                resumeOnce((nil, 0.0))
            }
        }
    }

    /// Map HTTP status to a friendly message (matches approach-6 main.py).
    static func httpMessage(_ status: Int) -> String {
        switch status {
        case 401: return "API Key 無效"
        case 403: return "API Key 權限不足"
        case 429: return "請求過於頻繁"
        default:  return "API 錯誤 HTTP \(status)"
        }
    }

    private static func elapsedMs(since start: DispatchTime) -> Int {
        let nanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }
}
