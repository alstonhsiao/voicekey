import XCTest
@testable import WhisperVoice

/// Live end-to-end smoke test against the real Grok + Cerebras APIs.
/// Generates speech with `say` + `afconvert` (no microphone needed).
/// Skipped unless RUN_LIVE_API_TESTS=1 (set keys via WHISPERVOICE_ENV_FILE or env vars).
final class LiveAPITests: XCTestCase {

    private var enabled: Bool {
        if ProcessInfo.processInfo.environment["RUN_LIVE_API_TESTS"] == "1" { return true }
        // Sentinel file: reliably controllable from the shell (env vars don't
        // propagate into the unit-test host process under `xcodebuild test`).
        let sentinel = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperVoice/.run_live_tests")
        return FileManager.default.fileExists(atPath: sentinel.path)
    }

    func testLiveGrokThenCerebras() async throws {
        try XCTSkipUnless(enabled, "create ~/Library/Application Support/WhisperVoice/.run_live_tests to run live API tests")
        let env = Secrets.loadEnv()
        guard let xai = env["XAI_API_KEY"], !xai.isEmpty else {
            throw XCTSkip("no XAI_API_KEY available")
        }

        // English phrase + default voice = reliable speech for plumbing validation.
        let phrase = "Hello, this is a WhisperVoice native build test."
        let wav = try makeSpeechWAV(phrase)
        defer { try? FileManager.default.removeItem(at: wav) }

        let grokCfg = ProviderEndpoint(apiKey: xai, model: "grok-stt",
                                       endpoint: "https://api.x.ai/v1/stt")
        let grok = GrokProvider(cfg: grokCfg)
        let m = Mode(raw: [
            "id": "live", "name": "Live", "language": "en",
            "grok_keyterms": ["WhisperVoice"],
            "llm_prompt": "Proofread the English text. Output only the corrected text.",
        ])!

        let raw = try await grok.transcribe(wavURL: wav, mode: m)
        print("🟢 LIVE Grok STT → \(raw)")
        XCTAssertFalse(raw.trimmingCharacters(in: .whitespaces).isEmpty,
                       "Grok should return non-empty transcription")

        if let cere = env["CEREBRAS_API_KEY"], !cere.isEmpty {
            let cfg = CerebrasConfig(apiKey: cere, model: "gpt-oss-120b",
                                     endpoint: "https://api.cerebras.ai/v1/chat/completions",
                                     maxTokens: 2048)
            let provider = CerebrasProvider(cfg: cfg)
            let corrected = await provider.correct(text: raw, mode: m, extraSystemPrompt: "")
            print("🟢 LIVE Cerebras → \(corrected)")
            XCTAssertFalse(corrected.isEmpty, "Cerebras should return non-empty text")
        }
    }

    // MARK: - Helpers

    private func makeSpeechWAV(_ text: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let aiff = tmp.appendingPathComponent("\(UUID().uuidString).aiff")
        let wav = tmp.appendingPathComponent("\(UUID().uuidString).wav")
        try run("/usr/bin/say", ["-o", aiff.path, text])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        try? FileManager.default.removeItem(at: aiff)
        return wav
    }

    private func run(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "LiveAPITests", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(launchPath) failed"])
        }
    }
}
