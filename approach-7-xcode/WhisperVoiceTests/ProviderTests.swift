import XCTest
@testable import WhisperVoice

final class ProviderTests: XCTestCase {

    private func mode(_ raw: [String: Any]) -> Mode {
        guard let m = Mode(raw: raw) else { fatalError("bad mode") }
        return m
    }

    private func bodyString(_ req: URLRequest) -> String {
        String(decoding: req.httpBody ?? Data(), as: UTF8.self)
    }

    // MARK: - Grok

    func testGrokRequestIncludesLanguageKeytermsAndFile() {
        let cfg = ProviderEndpoint(apiKey: "test-key", model: "grok-stt",
                                   endpoint: "https://api.x.ai/v1/stt")
        let provider = GrokProvider(cfg: cfg)
        let m = mode(["id": "direct", "name": "D", "language": "zh-TW",
                      "grok_keyterms": ["蕭淳云", "n8n"]])
        let req = provider.makeRequest(wavData: Data([1, 2, 3]), mode: m)

        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = bodyString(req)
        XCTAssertTrue(body.contains("name=\"language\""))
        XCTAssertTrue(body.contains("zh-TW"))
        XCTAssertTrue(body.contains("name=\"keyterm\""))
        XCTAssertTrue(body.contains("蕭淳云"))
        XCTAssertTrue(body.contains("n8n"))
        XCTAssertTrue(body.contains("filename=\"voice.wav\""))
    }

    func testGrokTranslateUsesEnglishLanguage() {
        let cfg = ProviderEndpoint(apiKey: "k", model: "grok-stt", endpoint: "https://api.x.ai/v1/stt")
        let provider = GrokProvider(cfg: cfg)
        let m = mode(["id": "zh2en", "name": "EN", "language": "zh",
                      "translate_to_english": true])
        let req = provider.makeRequest(wavData: Data([0]), mode: m)
        let body = bodyString(req)
        // language field present with value "en"
        XCTAssertTrue(body.contains("name=\"language\""))
        XCTAssertTrue(body.contains("en\r\n"))
    }

    func testGrokKeytermLimitAndLength() {
        let cfg = ProviderEndpoint(apiKey: "k", model: "grok-stt", endpoint: "https://api.x.ai/v1/stt")
        let provider = GrokProvider(cfg: cfg)
        let many = (1...15).map { "kw\($0)" }
        let tooLong = String(repeating: "x", count: 60)
        let m = mode(["id": "d", "name": "D", "language": "zh",
                      "grok_keyterms": many + [tooLong]])
        let req = provider.makeRequest(wavData: Data([0]), mode: m)
        let body = bodyString(req)
        let count = body.components(separatedBy: "name=\"keyterm\"").count - 1
        XCTAssertLessThanOrEqual(count, 10)        // capped at 10
        XCTAssertFalse(body.contains(tooLong))     // >50 chars dropped
    }

    // MARK: - OpenAI

    func testOpenAITranslateSwapsEndpointAndDropsLanguage() {
        let cfg = ProviderEndpoint(apiKey: "k", model: "gpt-4o-transcribe",
                                   endpoint: "https://api.openai.com/v1/audio/transcriptions")
        let provider = OpenAIProvider(cfg: cfg, temperature: 0.0)
        let m = mode(["id": "zh2en", "name": "EN", "language": "zh",
                      "translate_to_english": true, "prompt": "p"])
        let req = provider.makeRequest(wavData: Data([0]), mode: m)
        XCTAssertTrue(req.url!.absoluteString.contains("/translations"))
        XCTAssertFalse(bodyString(req).contains("name=\"language\""))
    }

    func testOpenAIIncludesModelAndResponseFormat() {
        let cfg = ProviderEndpoint(apiKey: "k", model: "gpt-4o-transcribe",
                                   endpoint: "https://api.openai.com/v1/audio/transcriptions")
        let provider = OpenAIProvider(cfg: cfg, temperature: 0.0)
        let m = mode(["id": "d", "name": "D", "language": "zh-TW", "prompt": "hint"])
        let body = bodyString(provider.makeRequest(wavData: Data([0]), mode: m))
        XCTAssertTrue(body.contains("gpt-4o-transcribe"))
        XCTAssertTrue(body.contains("response_format"))
        XCTAssertTrue(body.contains("hint"))
    }

    // MARK: - Cerebras

    func testCerebrasRequestBody() throws {
        let cfg = CerebrasConfig(apiKey: "k", model: "gpt-oss-120b",
                                 endpoint: "https://api.cerebras.ai/v1/chat/completions",
                                 maxTokens: 2048)
        let provider = CerebrasProvider(cfg: cfg)
        let req = provider.makeRequest(text: "輸入文字", systemPrompt: "系統提示")
        let json = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "gpt-oss-120b")
        XCTAssertEqual(json["max_tokens"] as? Int, 2048)
        XCTAssertEqual(json["temperature"] as? Double, 0.0)
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "系統提示")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "輸入文字")
    }

    func testCerebrasParsesContentAndFinishReason() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"choices":[{"message":{"content":"修正後文字"},"finish_reason":"stop"}]}
            """
            return (resp, Data(body.utf8))
        }
        let cfg = CerebrasConfig(apiKey: "k", model: "m",
                                 endpoint: "https://api.cerebras.ai/v1/chat/completions", maxTokens: 100)
        let provider = CerebrasProvider(cfg: cfg, session: MockURLProtocol.session())
        let m = mode(["id": "d", "name": "D", "llm_prompt": "修正"])
        let out = await provider.correct(text: "原文", mode: m, extraSystemPrompt: "")
        XCTAssertEqual(out, "修正後文字")
        XCTAssertEqual(provider.lastFinishReason, "stop")
    }

    func testCerebrasFallbackReturnsOriginalOnHTTPError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("err".utf8))
        }
        let cfg = CerebrasConfig(apiKey: "k", model: "m",
                                 endpoint: "https://api.cerebras.ai/v1/chat/completions", maxTokens: 100)
        let provider = CerebrasProvider(cfg: cfg, session: MockURLProtocol.session())
        let m = mode(["id": "d", "name": "D", "llm_prompt": "修正"])
        let out = await provider.correct(text: "原文不變", mode: m, extraSystemPrompt: "")
        XCTAssertEqual(out, "原文不變")   // degrade, never throws
    }

    func testCerebrasSkipsWhenNoPrompt() async {
        let cfg = CerebrasConfig(apiKey: "k", model: "m",
                                 endpoint: "https://api.cerebras.ai/v1/chat/completions", maxTokens: 100)
        let provider = CerebrasProvider(cfg: cfg, session: MockURLProtocol.session())
        let m = mode(["id": "d", "name": "D"])   // no llm_prompt
        let out = await provider.correct(text: "不動", mode: m, extraSystemPrompt: "")
        XCTAssertEqual(out, "不動")
    }
}
