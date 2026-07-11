import Foundation

/// LLM correction interface. Mirrors approach-6 `_voice_providers.LLMCorrectionProvider`.
/// ⚠️ `correct` NEVER throws — any failure returns the original text (degrade).
protocol LLMCorrectionProvider: AnyObject {
    var name: String { get }
    var lastFinishReason: String? { get }
    func correct(text: String, mode: Mode, extraSystemPrompt: String) async -> String
}

/// Cerebras fast LLM correction (Llama / Qwen / gpt-oss).
final class CerebrasProvider: LLMCorrectionProvider {
    let name = "cerebras"
    private(set) var lastFinishReason: String?
    private let cfg: CerebrasConfig
    private let session: URLSession

    init(cfg: CerebrasConfig, session: URLSession = .shared) {
        self.cfg = cfg
        self.session = session
    }

    func makeRequest(text: String, systemPrompt: String) -> URLRequest {
        var req = URLRequest(url: URL(string: cfg.endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": cfg.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "max_tokens": cfg.maxTokens,
            "temperature": 0.0,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    func correct(text: String, mode: Mode, extraSystemPrompt: String = "") async -> String {
        lastFinishReason = nil
        guard !mode.llmPrompt.isEmpty, !text.isEmpty else { return text }

        var system = mode.llmPrompt
        if !extraSystemPrompt.isEmpty { system += "\n\n" + extraSystemPrompt }

        do {
            let req = makeRequest(text: text, systemPrompt: system)
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                throw STTHTTPError(status: code)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first,
                  let message = choice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return text
            }
            lastFinishReason = choice["finish_reason"] as? String
            if lastFinishReason == "length" {
                AppLog.warn("⚠️ Cerebras 輸出被截斷（finish_reason=length，max_tokens=\(cfg.maxTokens)）")
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            AppLog.warn("⚠️ Cerebras 修正失敗（\(error)），使用原始文字")
            return text
        }
    }
}

enum LLMCorrectionProviders {
    /// Build the LLM corrector, or nil if disabled / unavailable.
    static func build(_ api: APIConfig, session: URLSession = .shared) -> LLMCorrectionProvider? {
        guard let llm = api.llmCorrection, llm.provider != "none" else { return nil }
        switch llm.provider {
        case "cerebras":
            guard let c = llm.cerebras else { return nil }
            if c.apiKey.isEmpty {
                AppLog.warn("⚠️ llm_correction.cerebras 缺少 api_key，已停用 LLM 修正")
                return nil
            }
            return CerebrasProvider(cfg: c, session: session)
        default:
            AppLog.warn("⚠️ 找不到 llm_correction provider：\(llm.provider)，已停用修正")
            return nil
        }
    }
}
