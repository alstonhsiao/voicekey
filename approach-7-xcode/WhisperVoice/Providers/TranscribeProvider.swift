import Foundation

/// HTTP error from an STT provider (non-2xx). Status mapped to a friendly
/// message by the caller (VoiceController), matching approach-6 main.py.
struct STTHTTPError: Error {
    let status: Int
}

/// STT provider interface. Mirrors approach-6 `_voice_providers.TranscribeProvider`.
protocol TranscribeProvider {
    var name: String { get }
    func transcribe(wavURL: URL, mode: Mode) async throws -> String
}

// MARK: - Grok (xAI)

/// xAI Grok STT — https://api.x.ai/v1/stt
/// Fields: language + repeated keyterm (≤10, each ≤50 chars) + file (last).
/// No `model` field. Response: JSON {"text": ...}.
final class GrokProvider: TranscribeProvider {
    let name = "grok"
    private let cfg: ProviderEndpoint
    private let session: URLSession

    init(cfg: ProviderEndpoint, session: URLSession = .shared) {
        self.cfg = cfg
        self.session = session
    }

    func makeRequest(wavData: Data, mode: Mode) -> URLRequest {
        var req = URLRequest(url: URL(string: cfg.endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")

        var mp = MultipartBuilder()
        let lang = mode.translateToEnglish ? "en" : mode.language
        mp.addField("language", lang)
        for kt in mode.grokKeyterms.prefix(10) where kt.count <= 50 {
            mp.addField("keyterm", kt)
        }
        mp.addFile(name: "file", filename: "voice.wav", contentType: "audio/wav", data: wavData)

        req.setValue(mp.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = mp.finalize()
        return req
    }

    func transcribe(wavURL: URL, mode: Mode) async throws -> String {
        let wavData = try Data(contentsOf: wavURL)
        let req = makeRequest(wavData: wavData, mode: mode)
        let (data, resp) = try await session.data(for: req)
        try checkStatus(resp)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - OpenAI

/// OpenAI Whisper / gpt-4o-transcribe. multipart: model/language/temperature/
/// response_format=text/prompt. translate → /translations endpoint, drop language.
final class OpenAIProvider: TranscribeProvider {
    let name: String
    private let cfg: ProviderEndpoint
    private let temperature: Double
    private let session: URLSession

    init(name: String = "openai", cfg: ProviderEndpoint, temperature: Double, session: URLSession = .shared) {
        self.name = name
        self.cfg = cfg
        self.temperature = temperature
        self.session = session
    }

    func makeRequest(wavData: Data, mode: Mode) -> URLRequest {
        var urlStr = cfg.endpoint
        var fields: [(String, String)] = [
            ("model", cfg.model),
            ("language", mode.language),
            ("temperature", String(temperature)),
            ("response_format", "text"),
            ("prompt", mode.prompt),
        ]
        if mode.translateToEnglish {
            urlStr = urlStr.replacingOccurrences(of: "/transcriptions", with: "/translations")
            fields.removeAll { $0.0 == "language" }
        }
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")

        var mp = MultipartBuilder()
        for (k, v) in fields { mp.addField(k, v) }
        mp.addFile(name: "file", filename: "voice.wav", contentType: "audio/wav", data: wavData)
        req.setValue(mp.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = mp.finalize()
        return req
    }

    func transcribe(wavURL: URL, mode: Mode) async throws -> String {
        let wavData = try Data(contentsOf: wavURL)
        let req = makeRequest(wavData: wavData, mode: mode)
        let (data, resp) = try await session.data(for: req)
        try checkStatus(resp)
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Groq (OpenAI-compatible)

final class GroqProvider: TranscribeProvider {
    let name = "groq"
    private let inner: OpenAIProvider

    init(cfg: ProviderEndpoint, temperature: Double, session: URLSession = .shared) {
        self.inner = OpenAIProvider(name: "groq", cfg: cfg, temperature: temperature, session: session)
    }

    func transcribe(wavURL: URL, mode: Mode) async throws -> String {
        try await inner.transcribe(wavURL: wavURL, mode: mode)
    }
}

// MARK: - Status helper & factory

private func checkStatus(_ resp: URLResponse) throws {
    guard let http = resp as? HTTPURLResponse else { return }
    if !(200..<300).contains(http.statusCode) {
        throw STTHTTPError(status: http.statusCode)
    }
}

enum TranscribeProviders {
    /// Build the configured STT provider. Throws if api_key is missing.
    static func build(_ api: APIConfig, session: URLSession = .shared) throws -> TranscribeProvider {
        switch api.provider {
        case "openai":
            guard !api.openai.apiKey.isEmpty else { throw ConfigError(message: "❌ openai provider 缺少 api_key") }
            return OpenAIProvider(cfg: api.openai, temperature: api.temperature, session: session)
        case "groq":
            guard !api.groq.apiKey.isEmpty else { throw ConfigError(message: "❌ groq provider 缺少 api_key") }
            return GroqProvider(cfg: api.groq, temperature: api.temperature, session: session)
        case "grok":
            guard !api.grok.apiKey.isEmpty else { throw ConfigError(message: "❌ grok provider 缺少 api_key") }
            return GrokProvider(cfg: api.grok, session: session)
        default:
            throw ConfigError(message: "❌ 未知的 provider：\(api.provider)")
        }
    }
}
