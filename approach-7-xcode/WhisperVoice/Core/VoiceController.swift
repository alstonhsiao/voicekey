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

    private var isRecording = false
    private var isProcessing = false   // blocks new recording while transcribing
    private let lock = NSLock()

    /// Phase 4: menu bar observes state changes.
    var onStateChange: ((VoiceState) -> Void)?

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
        recorder.start()
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
            let (maybeURL, audioSec) = recorder.stop()
            guard let url = maybeURL else {
                setState(.idle)
                AppLog.warn("⚠️ 錄音時間太短，已忽略")
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }

            AppLog.info("🔄 辨識中... [\(mode.display)]")
            let t0 = Date()

            // 1. STT
            let raw: String
            do {
                raw = try await transcribe.transcribe(wavURL: url, mode: mode)
            } catch let e as STTHTTPError {
                AppLog.error("❌ \(Self.httpMessage(e.status))")
                sessionLogger.log(SessionRecord(
                    timestamp: SessionLogger.now(), modeId: mode.id, modeName: mode.name,
                    provider: transcribe.name, audioSec: (audioSec * 100).rounded() / 100,
                    errorType: "http_error", errorDetail: "HTTP \(e.status)"))
                setState(.error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                setState(.idle)
                return
            } catch {
                let isTimeout = (error as? URLError)?.code == .timedOut
                AppLog.error(isTimeout ? "❌ 網路逾時" : "❌ 發生錯誤：\(error)")
                sessionLogger.log(SessionRecord(
                    timestamp: SessionLogger.now(), modeId: mode.id, modeName: mode.name,
                    provider: transcribe.name, audioSec: (audioSec * 100).rounded() / 100,
                    errorType: isTimeout ? "timeout" : "unknown", errorDetail: "\(error)"))
                setState(.error)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                setState(.idle)
                return
            }
            let sttMs = Int(Date().timeIntervalSince(t0) * 1000)
            AppLog.debug("🪵 raw STT: \(raw)")

            // 2. regex fallback corrections
            let corrected = RegexCorrections.apply(raw, rules: mode.regexRules)
            guard !corrected.isEmpty else {
                AppLog.warn("⚠️ 辨識結果為空")
                setState(.idle)
                return
            }
            AppLog.debug("🪵 regex corrected: \(corrected)")

            // 3. LLM correction (layer2 injection; degrade on failure)
            let tLLM = Date()
            let usedLLM = (llm != nil && !mode.llmPrompt.isEmpty)
            var finalText = corrected
            if let llm, usedLLM {
                let injection = vocab.layer2.buildInjection()
                finalText = await llm.correct(text: corrected, mode: mode, extraSystemPrompt: injection)
                AppLog.debug("🪵 LLM corrected: \(finalText)")
            } else {
                AppLog.debug("🪵 LLM corrected: <skipped>")
            }
            let llmMs = Int(Date().timeIntervalSince(tLLM) * 1000)
            let llmOut: String? = usedLLM ? finalText : nil

            // 3b. Layer-3 user vocab pinyin fuzzy (degrade to original on any issue)
            var vocabOut: String?
            if let layer3 = vocab.layer3 {
                let applied = layer3.apply(finalText)
                if applied != finalText {
                    AppLog.debug("🪵 vocab corrected: \(applied)")
                }
                vocabOut = applied
                finalText = applied
            }

            // 4. paste into the target app
            let (method, ok) = await Paste.pasteText(finalText, targetApp: targetApp)
            AppLog.info("⏱  STT: \(sttMs)ms | LLM: \(llmMs)ms | audio: \(String(format: "%.2f", audioSec))s")
            AppLog.info("✅ 已貼上（\(method)，ok=\(ok)）：\(finalText)")
            setState(.idle)

            sessionLogger.log(SessionRecord(
                timestamp: SessionLogger.now(),
                modeId: mode.id, modeName: mode.name, provider: transcribe.name,
                audioSec: (audioSec * 100).rounded() / 100,
                rawStt: raw, regexOut: corrected, llmOut: llmOut, vocabOut: vocabOut,
                finalText: finalText, sttMs: sttMs, llmMs: usedLLM ? llmMs : nil,
                pasteMethod: method, pasteOk: ok ? 1 : 0,
                llmFinishReason: llm?.lastFinishReason))
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
}
